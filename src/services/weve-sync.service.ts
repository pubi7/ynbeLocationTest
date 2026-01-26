import prisma from "../db/prisma";
import logger from "../utils/logger";
import weveService from "./weve.service";
import weveAuthService from "./weve-auth.service";

/**
 * Weve Auto-Sync Service
 * Automatically syncs products from Weve and pushes orders to Weve
 */

interface SyncResult {
  success: boolean;
  productsAdded?: number;
  productsUpdated?: number;
  productsSkipped?: number;
  message?: string;
  errors?: string[];
}

interface OrderPushResult {
  success: boolean;
  orderId: number;
  weveOrderId?: string;
  message?: string;
}

class WeveSyncService {
  private isSyncing = false;
  private lastSyncTime: Date | null = null;

  /**
   * Auto-sync products from Weve to aguulga3
   * Called periodically or manually
   */
  async syncProductsFromWeve(): Promise<SyncResult> {
    if (this.isSyncing) {
      return {
        success: false,
        message: "Sync already in progress",
      };
    }

    if (!weveAuthService.isLoggedIn()) {
      return {
        success: false,
        message: "Not logged in to Weve. Please login first.",
      };
    }

    this.isSyncing = true;
    logger.info("Starting automatic product sync from Weve");

    const result: SyncResult = {
      success: true,
      productsAdded: 0,
      productsUpdated: 0,
      productsSkipped: 0,
      errors: [],
    };

    try {
      // Fetch all active products from Weve
      let page = 1;
      let hasMore = true;
      const limit = 100;

      while (hasMore) {
        const response = await weveService.fetchProducts({
          page,
          limit,
          isActive: true,
        });

        if (!response.success || !response.data) {
          result.errors?.push(
            `Failed to fetch page ${page}: ${response.message}`
          );
          break;
        }

        const { products, total } = response.data;

        for (const weveProduct of products) {
          try {
            // Check if product exists by product code or barcode
            const existingProduct = await prisma.product.findFirst({
              where: {
                OR: [
                  { productCode: weveProduct.productCode || undefined },
                  { barcode: weveProduct.barcode || undefined },
                ],
              },
            });

            if (existingProduct) {
              // Update existing product
              await prisma.product.update({
                where: { id: existingProduct.id },
                data: {
                  nameMongolian:
                    weveProduct.nameMongolian || weveProduct.name,
                  nameEnglish: weveProduct.nameEnglish,
                  priceRetail: weveProduct.price,
                  stockQuantity: weveProduct.stockQuantity,
                  isActive: weveProduct.isActive,
                },
              });

              result.productsUpdated!++;
              logger.info(`Updated product: ${weveProduct.name}`, {
                id: existingProduct.id,
              });
            } else {
              // Create new product
              await prisma.product.create({
                data: {
                  nameMongolian:
                    weveProduct.nameMongolian || weveProduct.name,
                  nameEnglish: weveProduct.nameEnglish,
                  productCode: weveProduct.productCode,
                  barcode: weveProduct.barcode,
                  priceRetail: weveProduct.price,
                  stockQuantity: weveProduct.stockQuantity,
                  isActive: weveProduct.isActive,
                },
              });

              result.productsAdded!++;
              logger.info(`Added new product: ${weveProduct.name}`);
            }
          } catch (productError: any) {
            result.errors?.push(
              `Failed to sync product ${weveProduct.name}: ${productError.message}`
            );
            logger.error(`Failed to sync product ${weveProduct.name}`, {
              error: productError.message,
            });
          }
        }

        // Check if there are more pages
        hasMore = page * limit < total;
        page++;
      }

      this.lastSyncTime = new Date();

      logger.info("Product sync completed", {
        added: result.productsAdded,
        updated: result.productsUpdated,
        errors: result.errors?.length || 0,
      });

      result.message = `Sync completed: ${result.productsAdded} added, ${result.productsUpdated} updated`;
    } catch (error: any) {
      logger.error("Product sync failed", { error: error.message });
      result.success = false;
      result.message = `Sync failed: ${error.message}`;
    } finally {
      this.isSyncing = false;
    }

    return result;
  }

  /**
   * Auto-push order to Weve when created in aguulga3
   * Called automatically after order creation
   */
  async autoPushOrderToWeve(orderId: number): Promise<OrderPushResult> {
    if (!weveAuthService.isLoggedIn()) {
      logger.warn(`Cannot push order ${orderId}: Not logged in to Weve`);
      return {
        success: false,
        orderId,
        message: "Not logged in to Weve",
      };
    }

    try {
      // Fetch order details
      const order = await prisma.order.findUnique({
        where: { id: orderId },
        include: {
          customer: true,
          orderItems: {
            include: {
              product: true,
            },
          },
        },
      });

      if (!order) {
        return {
          success: false,
          orderId,
          message: "Order not found",
        };
      }

      // Only push Store type orders
      if (order.orderType !== "Store") {
        logger.info(
          `Skipping order ${orderId}: Not a Store order (type: ${order.orderType})`
        );
        return {
          success: false,
          orderId,
          message: "Only Store orders are pushed to Weve",
        };
      }

      // Prepare order data
      const weveOrder = {
        orderNumber: order.orderNumber || `ORD-${order.id}`,
        customerId: order.customer?.legacyCustomerId,
        customerName: order.customer?.name,
        customerPhone: order.customer?.phoneNumber || undefined,
        customerAddress: order.customer?.address || undefined,
        items: order.orderItems.map((item) => ({
          productId: item.product.id,
          productCode: item.product.productCode || undefined,
          quantity: item.quantity,
          unitPrice: parseFloat(item.unitPrice.toString()),
          totalPrice: parseFloat(
            (item.quantity * parseFloat(item.unitPrice.toString())).toFixed(2)
          ),
        })),
        subtotalAmount: order.subtotalAmount
          ? parseFloat(order.subtotalAmount.toString())
          : parseFloat(order.totalAmount?.toString() || "0"),
        vatAmount: order.vatAmount
          ? parseFloat(order.vatAmount.toString())
          : 0,
        totalAmount: order.totalAmount
          ? parseFloat(order.totalAmount.toString())
          : 0,
        orderDate: order.orderDate.toISOString(),
        status: order.status,
      };

      // Push to Weve
      const result = await weveService.pushOrder(weveOrder);

      if (result.success) {
        logger.info(`Order ${orderId} automatically pushed to Weve`, {
          weveOrderId: result.data?.weveOrderId,
        });

        // Optionally: Store weveOrderId in database
        // You may need to add a field to Order model for this

        return {
          success: true,
          orderId,
          weveOrderId: result.data?.weveOrderId,
          message: "Order pushed to Weve successfully",
        };
      } else {
        logger.error(`Failed to push order ${orderId} to Weve`, {
          message: result.message,
        });

        return {
          success: false,
          orderId,
          message: result.message || "Failed to push order to Weve",
        };
      }
    } catch (error: any) {
      logger.error(`Error pushing order ${orderId} to Weve`, {
        error: error.message,
      });

      return {
        success: false,
        orderId,
        message: error.message || "Unknown error",
      };
    }
  }

  /**
   * Get last sync time
   */
  getLastSyncTime(): Date | null {
    return this.lastSyncTime;
  }

  /**
   * Check if currently syncing
   */
  isSyncInProgress(): boolean {
    return this.isSyncing;
  }

  /**
   * Manual sync trigger (for UI button)
   */
  async triggerManualSync(): Promise<SyncResult> {
    logger.info("Manual product sync triggered");
    return this.syncProductsFromWeve();
  }

  /**
   * Sync products for specific category
   */
  async syncProductsByCategory(categoryId: number): Promise<SyncResult> {
    if (!weveAuthService.isLoggedIn()) {
      return {
        success: false,
        message: "Not logged in to Weve",
      };
    }

    logger.info(`Syncing products for category ${categoryId}`);

    const result = await weveService.fetchProducts({
      categoryId,
      isActive: true,
      limit: 100,
    });

    if (!result.success || !result.data) {
      return {
        success: false,
        message: result.message || "Failed to fetch products",
      };
    }

    // Process products (similar to syncProductsFromWeve)
    const syncResult: SyncResult = {
      success: true,
      productsAdded: 0,
      productsUpdated: 0,
      errors: [],
    };

    for (const weveProduct of result.data.products) {
      try {
        const existingProduct = await prisma.product.findFirst({
          where: {
            OR: [
              { productCode: weveProduct.productCode || undefined },
              { barcode: weveProduct.barcode || undefined },
            ],
          },
        });

        if (existingProduct) {
          await prisma.product.update({
            where: { id: existingProduct.id },
            data: {
              nameMongolian: weveProduct.nameMongolian || weveProduct.name,
              nameEnglish: weveProduct.nameEnglish,
              priceRetail: weveProduct.price,
              stockQuantity: weveProduct.stockQuantity,
              categoryId,
            },
          });
          syncResult.productsUpdated!++;
        } else {
          await prisma.product.create({
            data: {
              nameMongolian: weveProduct.nameMongolian || weveProduct.name,
              nameEnglish: weveProduct.nameEnglish,
              productCode: weveProduct.productCode,
              barcode: weveProduct.barcode,
              priceRetail: weveProduct.price,
              stockQuantity: weveProduct.stockQuantity,
              categoryId,
              isActive: true,
            },
          });
          syncResult.productsAdded!++;
        }
      } catch (error: any) {
        syncResult.errors?.push(
          `Failed to sync ${weveProduct.name}: ${error.message}`
        );
      }
    }

    return syncResult;
  }
}

export default new WeveSyncService();
