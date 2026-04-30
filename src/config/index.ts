/**
 * Configuration file for Weve integration
 * Environment variables can be set via .env file or process.env
 */

interface WeveConfig {
  apiUrl: string;
  apiKey: string;
  timeout: number;
  mockMode: boolean;
}

interface Config {
  weve: WeveConfig;
}

const config: Config = {
  weve: {
    // Weve API URL - can be overridden via WEVE_API_URL environment variable
    apiUrl: process.env.WEVE_API_URL || "https://api.weve.mn/api",
    
    // Weve API Key (optional - for API key authentication)
    apiKey: process.env.WEVE_API_KEY || "",
    
    // Request timeout in milliseconds
    timeout: parseInt(process.env.WEVE_API_TIMEOUT || "30000", 10),
    
    // Mock mode - set to true to use mock responses instead of real API calls
    // Set WEVE_MOCK_MODE=false in environment to disable
    mockMode: process.env.WEVE_MOCK_MODE !== "false",
  },
};

export { config };
export type { Config, WeveConfig };
