import { Request, Response, NextFunction } from "express";
import weveAuthService from "../services/weve-auth.service";
import weveSyncService from "../services/weve-sync.service";
import { AppError } from "../middleware/error.middleware";
import logger from "../utils/logger";

/**
 * Login to Weve with aguulga3 credentials
 */
export const loginToWeve = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      throw new AppError("Username and password are required", 400);
    }

    const result = await weveAuthService.login(username, password);

    if (!result.success) {
      throw new AppError(
        result.message || "Failed to login to Weve",
        401
      );
    }

    res.json({
      status: "success",
      data: {
        token: result.token,
        userId: result.userId,
        userName: result.userName,
        expiresIn: result.expiresIn,
      },
      message: "Logged in to Weve successfully",
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Logout from Weve
 */
export const logoutFromWeve = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const result = await weveAuthService.logout();

    res.json({
      status: "success",
      message: result.message || "Logged out from Weve",
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Get current Weve session status
 */
export const getWeveSessionStatus = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const session = weveAuthService.getSession();

    if (!session) {
      res.json({
        status: "success",
        data: {
          isLoggedIn: false,
          session: null,
        },
      });
      return;
    }

    res.json({
      status: "success",
      data: {
        isLoggedIn: true,
        session: {
          userId: session.userId,
          userName: session.userName,
          expiresAt: session.expiresAt,
          isActive: session.isActive,
        },
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Refresh Weve auth token
 */
export const refreshWeveToken = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const result = await weveAuthService.refreshToken();

    if (!result.success) {
      throw new AppError("Failed to refresh token", 401);
    }

    res.json({
      status: "success",
      data: {
        token: result.token,
      },
      message: "Token refreshed successfully",
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Trigger manual product sync from Weve
 */
export const triggerProductSync = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    if (!weveAuthService.isLoggedIn()) {
      throw new AppError("Not logged in to Weve", 401);
    }

    const result = await weveSyncService.triggerManualSync();

    res.json({
      status: result.success ? "success" : "error",
      data: {
        productsAdded: result.productsAdded,
        productsUpdated: result.productsUpdated,
        productsSkipped: result.productsSkipped,
        errors: result.errors,
      },
      message: result.message,
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Get sync status
 */
export const getSyncStatus = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const lastSyncTime = weveSyncService.getLastSyncTime();
    const isSyncing = weveSyncService.isSyncInProgress();

    res.json({
      status: "success",
      data: {
        lastSyncTime,
        isSyncing,
        isLoggedIn: weveAuthService.isLoggedIn(),
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Sync products by category
 */
export const syncProductsByCategory = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const { categoryId } = req.params;

    if (!categoryId || isNaN(parseInt(categoryId))) {
      throw new AppError("Valid category ID is required", 400);
    }

    if (!weveAuthService.isLoggedIn()) {
      throw new AppError("Not logged in to Weve", 401);
    }

    const result = await weveSyncService.syncProductsByCategory(
      parseInt(categoryId)
    );

    res.json({
      status: result.success ? "success" : "error",
      data: {
        productsAdded: result.productsAdded,
        productsUpdated: result.productsUpdated,
        errors: result.errors,
      },
      message: result.message,
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Validate Weve credentials without logging in
 */
export const validateWeveCredentials = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      throw new AppError("Username and password are required", 400);
    }

    const result = await weveAuthService.validateCredentials(
      username,
      password
    );

    res.json({
      status: "success",
      data: {
        valid: result.valid,
      },
      message: result.message,
    });
  } catch (error) {
    next(error);
  }
};
