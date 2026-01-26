import axios, { AxiosInstance } from "axios";
import logger from "../utils/logger";
import { config } from "../config";

/**
 * Weve Authentication Service
 * Handles login/logout to Weve site using aguulga3 credentials
 */

interface WeveLoginResponse {
  success: boolean;
  token?: string;
  refreshToken?: string;
  userId?: number;
  userName?: string;
  expiresIn?: number;
  message?: string;
  errorCode?: string;
}

interface WeveAuthSession {
  token: string;
  refreshToken?: string;
  userId: number;
  userName: string;
  expiresAt: Date;
  isActive: boolean;
}

class WeveAuthService {
  private client: AxiosInstance;
  private session: WeveAuthSession | null = null;

  constructor() {
    this.client = axios.create({
      baseURL: config.weve.apiUrl,
      timeout: config.weve.timeout,
      headers: {
        "Content-Type": "application/json",
      },
    });
  }

  /**
   * Login to Weve site with aguulga3 credentials
   */
  async login(username: string, password: string): Promise<WeveLoginResponse> {
    if (config.weve.mockMode) {
      logger.warn("Weve mock mode enabled - returning mock login response");
      return {
        success: true,
        token: "mock_token_" + Date.now(),
        userId: 1,
        userName: username,
        expiresIn: 3600,
        message: "Mock login successful",
      };
    }

    try {
      const response = await this.client.post<{
        token: string;
        refreshToken?: string;
        userId: number;
        userName: string;
        expiresIn: number;
      }>("/auth/login", {
        username,
        password,
        source: "aguulga3", // Identify this is from aguulga3 system
      });

      // Store session
      const expiresAt = new Date();
      expiresAt.setSeconds(expiresAt.getSeconds() + response.data.expiresIn);

      this.session = {
        token: response.data.token,
        refreshToken: response.data.refreshToken,
        userId: response.data.userId,
        userName: response.data.userName,
        expiresAt,
        isActive: true,
      };

      logger.info(`Logged in to Weve as ${username}`, {
        userId: response.data.userId,
      });

      return {
        success: true,
        token: response.data.token,
        refreshToken: response.data.refreshToken,
        userId: response.data.userId,
        userName: response.data.userName,
        expiresIn: response.data.expiresIn,
      };
    } catch (error: any) {
      logger.error("Failed to login to Weve", {
        error: error.message,
        status: error.response?.status,
      });

      return {
        success: false,
        message:
          error.response?.data?.message ||
          error.message ||
          "Failed to login to Weve",
        errorCode: error.response?.data?.errorCode,
      };
    }
  }

  /**
   * Logout from Weve site
   */
  async logout(): Promise<{ success: boolean; message?: string }> {
    if (!this.session) {
      return { success: true, message: "No active session" };
    }

    if (config.weve.mockMode) {
      this.session = null;
      return { success: true, message: "Mock logout successful" };
    }

    try {
      await this.client.post(
        "/auth/logout",
        {},
        {
          headers: {
            Authorization: `Bearer ${this.session.token}`,
          },
        }
      );

      logger.info("Logged out from Weve", {
        userName: this.session.userName,
      });

      this.session = null;

      return { success: true, message: "Logged out successfully" };
    } catch (error: any) {
      logger.error("Failed to logout from Weve", { error: error.message });

      // Clear session anyway
      this.session = null;

      return {
        success: false,
        message: error.message || "Failed to logout",
      };
    }
  }

  /**
   * Get current session
   */
  getSession(): WeveAuthSession | null {
    if (!this.session) {
      return null;
    }

    // Check if session expired
    if (new Date() > this.session.expiresAt) {
      logger.warn("Weve session expired");
      this.session = null;
      return null;
    }

    return this.session;
  }

  /**
   * Get auth token for API requests
   */
  getAuthToken(): string | null {
    const session = this.getSession();
    return session?.token || null;
  }

  /**
   * Check if logged in
   */
  isLoggedIn(): boolean {
    return this.getSession() !== null;
  }

  /**
   * Refresh access token
   */
  async refreshToken(): Promise<{ success: boolean; token?: string }> {
    if (!this.session?.refreshToken) {
      return { success: false };
    }

    if (config.weve.mockMode) {
      return {
        success: true,
        token: "mock_refreshed_token_" + Date.now(),
      };
    }

    try {
      const response = await this.client.post<{
        token: string;
        expiresIn: number;
      }>("/auth/refresh", {
        refreshToken: this.session.refreshToken,
      });

      // Update session
      const expiresAt = new Date();
      expiresAt.setSeconds(expiresAt.getSeconds() + response.data.expiresIn);

      this.session.token = response.data.token;
      this.session.expiresAt = expiresAt;

      logger.info("Refreshed Weve token");

      return {
        success: true,
        token: response.data.token,
      };
    } catch (error: any) {
      logger.error("Failed to refresh Weve token", {
        error: error.message,
      });

      // Clear session on refresh failure
      this.session = null;

      return { success: false };
    }
  }

  /**
   * Validate credentials without logging in
   */
  async validateCredentials(
    username: string,
    password: string
  ): Promise<{ valid: boolean; message?: string }> {
    if (config.weve.mockMode) {
      return { valid: true, message: "Mock validation successful" };
    }

    try {
      await this.client.post("/auth/validate", {
        username,
        password,
      });

      return { valid: true };
    } catch (error: any) {
      return {
        valid: false,
        message:
          error.response?.data?.message || "Invalid credentials",
      };
    }
  }
}

export default new WeveAuthService();
