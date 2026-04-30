import { Router } from "express";
import { body, param } from "express-validator";
import { validate } from "../middleware/validation.middleware";
import { authMiddleware, checkRole } from "../middleware/auth.middleware";
import {
  loginToWeve,
  logoutFromWeve,
  getWeveSessionStatus,
  refreshWeveToken,
  triggerProductSync,
  getSyncStatus,
  syncProductsByCategory,
  validateWeveCredentials,
} from "../controllers/weve-auth.controller";

const router = Router();

// All routes require authentication
router.use(authMiddleware);

/**
 * @swagger
 * /api/weve/auth/login:
 *   post:
 *     summary: Login to Weve with aguulga3 credentials
 *     tags: [Weve Auth]
 *     security:
 *       - bearerAuth: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - username
 *               - password
 *             properties:
 *               username:
 *                 type: string
 *                 example: admin@aguulga3
 *               password:
 *                 type: string
 *                 example: your_password
 *     responses:
 *       200:
 *         description: Logged in successfully
 *       401:
 *         description: Invalid credentials
 */
router.post(
  "/auth/login",
  checkRole(["Admin", "Manager", "StoreManager"]),
  validate([
    body("username")
      .notEmpty()
      .withMessage("Username is required")
      .isString(),
    body("password")
      .notEmpty()
      .withMessage("Password is required")
      .isString(),
  ]),
  loginToWeve
);

/**
 * @swagger
 * /api/weve/auth/logout:
 *   post:
 *     summary: Logout from Weve
 *     tags: [Weve Auth]
 *     security:
 *       - bearerAuth: []
 *     responses:
 *       200:
 *         description: Logged out successfully
 */
router.post(
  "/auth/logout",
  checkRole(["Admin", "Manager", "StoreManager"]),
  logoutFromWeve
);

/**
 * @swagger
 * /api/weve/auth/session:
 *   get:
 *     summary: Get current Weve session status
 *     tags: [Weve Auth]
 *     security:
 *       - bearerAuth: []
 *     responses:
 *       200:
 *         description: Session status retrieved
 */
router.get("/auth/session", getWeveSessionStatus);

/**
 * @swagger
 * /api/weve/auth/refresh:
 *   post:
 *     summary: Refresh Weve auth token
 *     tags: [Weve Auth]
 *     security:
 *       - bearerAuth: []
 *     responses:
 *       200:
 *         description: Token refreshed successfully
 *       401:
 *         description: Failed to refresh token
 */
router.post(
  "/auth/refresh",
  checkRole(["Admin", "Manager", "StoreManager"]),
  refreshWeveToken
);

/**
 * @swagger
 * /api/weve/auth/validate:
 *   post:
 *     summary: Validate Weve credentials without logging in
 *     tags: [Weve Auth]
 *     security:
 *       - bearerAuth: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - username
 *               - password
 *             properties:
 *               username:
 *                 type: string
 *               password:
 *                 type: string
 *     responses:
 *       200:
 *         description: Validation result
 */
router.post(
  "/auth/validate",
  checkRole(["Admin", "Manager", "StoreManager"]),
  validate([
    body("username").notEmpty().isString(),
    body("password").notEmpty().isString(),
  ]),
  validateWeveCredentials
);

/**
 * @swagger
 * /api/weve/sync/trigger:
 *   post:
 *     summary: Trigger manual product sync from Weve
 *     tags: [Weve Sync]
 *     security:
 *       - bearerAuth: []
 *     responses:
 *       200:
 *         description: Sync completed
 *       401:
 *         description: Not logged in to Weve
 */
router.post(
  "/sync/trigger",
  checkRole(["Admin", "Manager", "StoreManager"]),
  triggerProductSync
);

/**
 * @swagger
 * /api/weve/sync/status:
 *   get:
 *     summary: Get sync status
 *     tags: [Weve Sync]
 *     security:
 *       - bearerAuth: []
 *     responses:
 *       200:
 *         description: Sync status retrieved
 */
router.get("/sync/status", getSyncStatus);

/**
 * @swagger
 * /api/weve/sync/category/{categoryId}:
 *   post:
 *     summary: Sync products for specific category
 *     tags: [Weve Sync]
 *     security:
 *       - bearerAuth: []
 *     parameters:
 *       - in: path
 *         name: categoryId
 *         required: true
 *         schema:
 *           type: integer
 *     responses:
 *       200:
 *         description: Category sync completed
 *       401:
 *         description: Not logged in to Weve
 */
router.post(
  "/sync/category/:categoryId",
  checkRole(["Admin", "Manager", "StoreManager"]),
  validate([param("categoryId").isInt()]),
  syncProductsByCategory
);

export default router;
