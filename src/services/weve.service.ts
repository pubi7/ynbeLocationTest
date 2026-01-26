import axios, { AxiosInstance } from "axios";
import logger from "../utils/logger";
import { config } from "../config";

/**
 * Weve Service
 * Handles communication with Weve e-commerce site API
 */

interface FetchProductsParams {
  page?: number;
  limit?: number;
  categoryId?: number;
  isActive?: boolean;
}

interface WeveProduct {
  id: number;
  name: string;
  nameMongolian?: string;
  nameEnglish?: string;
  productCode?: string;
  barcode?: string;
  price: number;
  stockQuantity?: number;
  isActive?: boolean;
}

interface FetchProductsResponse {
  success: boolean;
  data?: {
    products: WeveProduct[];
    total: number;
  };
  message?: string;
}

interface PushOrderParams {
  orderNumber: string;
  customerId?: number;
  customerName?: string;
  customerPhone?: string;
  customerAddress?: string;
  items: Array<{
    productId: number;
    productCode?: string;
    quantity: number;
    unitPrice: number;
    totalPrice: number;
  }>;
  subtotalAmount: number;
  vatAmount?: number;
  totalAmount: number;
  orderDate: string;
  status?: string;
}

interface PushOrderResponse {
  success: boolean;
  data?: {
    weveOrderId?: string;
  };
  message?: string;
}

class WeveService {
  private client: AxiosInstance | null = null;
  private isEnabled: boolean = false;

  constructor() {
    this.isEnabled = !config.weve.mockMode && !!config.weve.apiUrl;

    if (this.isEnabled) {
      this.client = axios.create({
        baseURL: config.weve.apiUrl,
        timeout: config.weve.timeout,
        headers: {
          "Content-Type": "application/json",
          ...(config.weve.apiKey && { "X-API-Key": config.weve.apiKey }),
        },
      });
    }
  }

  /**
   * Fetch products from Weve
   */
  async fetchProducts(
    params: FetchProductsParams = {}
  ): Promise<FetchProductsResponse> {
    if (config.weve.mockMode) {
      logger.warn("Weve mock mode - returning mock products");
      return {
        success: true,
        data: {
          products: [],
          total: 0,
        },
        message: "Mock mode: No products returned",
      };
    }

    if (!this.isEnabled || !this.client) {
      return {
        success: false,
        message: "Weve service is not enabled or configured",
      };
    }

    try {
      const response = await this.client.get<{
        products: WeveProduct[];
        total: number;
      }>("/products", {
        params: {
          page: params.page || 1,
          limit: params.limit || 100,
          ...(params.categoryId && { categoryId: params.categoryId }),
          ...(params.isActive !== undefined && { isActive: params.isActive }),
        },
      });

      return {
        success: true,
        data: {
          products: response.data.products || [],
          total: response.data.total || 0,
        },
      };
    } catch (error: any) {
      logger.error("Failed to fetch products from Weve", {
        error: error.message,
        status: error.response?.status,
      });

      return {
        success: false,
        message:
          error.response?.data?.message ||
          error.message ||
          "Failed to fetch products from Weve",
      };
    }
  }

  /**
   * Push order to Weve
   */
  async pushOrder(order: PushOrderParams): Promise<PushOrderResponse> {
    if (config.weve.mockMode) {
      logger.warn("Weve mock mode - simulating order push");
      return {
        success: true,
        data: {
          weveOrderId: `MOCK-${Date.now()}`,
        },
        message: "Mock mode: Order push simulated",
      };
    }

    if (!this.isEnabled || !this.client) {
      return {
        success: false,
        message: "Weve service is not enabled or configured",
      };
    }

    try {
      const response = await this.client.post<{
        weveOrderId?: string;
        message?: string;
      }>("/orders", order);

      return {
        success: true,
        data: {
          weveOrderId: response.data.weveOrderId,
        },
        message: response.data.message || "Order pushed successfully",
      };
    } catch (error: any) {
      logger.error("Failed to push order to Weve", {
        error: error.message,
        status: error.response?.status,
        orderNumber: order.orderNumber,
      });

      return {
        success: false,
        message:
          error.response?.data?.message ||
          error.message ||
          "Failed to push order to Weve",
      };
    }
  }
}

export default new WeveService();
