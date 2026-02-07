const express = require('express');
const cors = require('cors');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 3001;

// Warehouse Backend API Configuration (warehouse-service-main runs on port 4000)
const WAREHOUSE_API_URL = process.env.WAREHOUSE_API_URL || 'http://localhost:3000/api';
const WAREHOUSE_API_KEY = process.env.WAREHOUSE_API_KEY || '';

app.use(cors());
app.use(express.json());

// Helper function to get headers for Warehouse API
function getApiHeaders(req) {
    const headers = {
        'Content-Type': 'application/json',
    };
    if (WAREHOUSE_API_KEY) {
        headers['X-API-Key'] = WAREHOUSE_API_KEY;
    }
    // Forward auth token if present
    const authHeader = req.headers.authorization;
    if (authHeader) {
        headers['Authorization'] = authHeader;
    }
    return headers;
}

// --- AUTH ROUTES ---
app.post('/api/auth/login', async (req, res) => {
    const identifier = req.body.identifier || req.body.email;
    const password = req.body.password;
    console.log('Login attempt:', identifier);

    try {
        const response = await axios.post(`${WAREHOUSE_API_URL}/auth/login`, {
            identifier: identifier,
            password: password
        }, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 30000
        });

        console.log('✅ Login successful via Warehouse API');
        
        // Warehouse backend returns: { status: 'success', data: { token, user } }
        const userData = response.data.data || response.data;
        
        return res.json({
            status: 'success',
            data: {
                user: userData.user || {
                    id: userData.userId,
                    name: userData.userName || identifier,
                    email: identifier,
                    role: userData.role || 'user'
                },
                token: userData.token
            }
        });
    } catch (error) {
        console.error('❌ Login failed:', error.message);
        console.error('   Status:', error.response?.status);
        console.error('   Response:', error.response?.data);
        
        res.status(error.response?.status || 401).json({
            status: 'error',
            message: error.response?.data?.message || 'Имэйл эсвэл нууц үг буруу байна'
        });
    }
});

// Agent login endpoint
app.post('/api/auth/agent-login', async (req, res) => {
    const username = req.body.username || req.body.identifier || req.body.email;
    const password = req.body.password;
    console.log('Agent login attempt:', username);

    try {
        const response = await axios.post(`${WAREHOUSE_API_URL}/auth/login`, {
            identifier: username,
            password: password
        }, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 30000
        });

        console.log('✅ Agent login successful');
        const userData = response.data.data || response.data;
        
        res.json({
            status: 'success',
            data: {
                token: userData.token,
                agent: userData.user || {
                    id: userData.userId,
                    username: username,
                    name: userData.userName || username,
                    email: username
                }
            }
        });
    } catch (error) {
        console.error('❌ Agent login failed:', error.message);
        res.status(error.response?.status || 401).json({
            status: 'error',
            message: error.response?.data?.message || 'Нэвтрэх нэр эсвэл нууц үг буруу байна'
        });
    }
});

// Get user profile endpoint - decode JWT token to get user info
app.get('/api/auth/profile', async (req, res) => {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({
            status: 'error',
            message: 'Token шаардлагатай'
        });
    }

    try {
        const token = authHeader.split(' ')[1];
        // Decode JWT token (without verification - warehouse backend handles that)
        const base64Payload = token.split('.')[1];
        const payload = JSON.parse(Buffer.from(base64Payload, 'base64').toString('utf8'));
        
        console.log('✅ Profile decoded from JWT token');
        res.json({
            status: 'success',
            data: {
                user: {
                    id: payload.userId || payload.id || payload.sub,
                    name: payload.name || payload.userName || 'User',
                    email: payload.email || payload.identifier || '',
                    role: payload.role || payload.roleName || 'user'
                }
            }
        });
    } catch (error) {
        console.error('❌ Profile decode failed:', error.message);
        res.status(401).json({
            status: 'error',
            message: 'Token буруу байна'
        });
    }
});

// --- PRODUCT ROUTES ---
app.get('/api/products', async (req, res) => {
    console.log('Fetching products from Warehouse API...', req.query);
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 200;
    const includeInactive = req.query.includeInactive !== 'false';
    
    try {
        console.log(`📦 Requesting products from: ${WAREHOUSE_API_URL}/products`);
        
        const weveParams = {
            page: page,
            limit: limit,
        };
        if (!includeInactive) {
            weveParams.isActive = true;
        }
        
        const response = await axios.get(`${WAREHOUSE_API_URL}/products`, {
            headers: getApiHeaders(req),
            params: weveParams,
            timeout: 30000
        });
        
        const products = response.data.products || response.data.data?.products || [];
        const total = response.data.total || response.data.data?.total || products.length;
        
        console.log(`✅ Successfully fetched ${products.length} products from Warehouse`);
        
        res.json({
            status: 'success',
            data: {
                products: products,
                pagination: {
                    page: page,
                    limit: limit,
                    total: total,
                    totalPages: Math.ceil(total / limit)
                }
            }
        });
    } catch (error) {
        console.error('❌ Failed to fetch products from Warehouse API:', error.message);
        console.error('   Status:', error.response?.status);
        console.error('   Response:', error.response?.data);
        
        res.status(error.response?.status || 500).json({
            status: 'error',
            message: error.response?.data?.message || 'Бүтээгдэхүүн авахад алдаа гарлаа',
            data: {
                products: [],
                pagination: { page: 1, limit: limit, total: 0, totalPages: 0 }
            }
        });
    }
});

app.post('/api/products', async (req, res) => {
    console.log('Creating product in Warehouse API:', req.body);
    
    try {
        const response = await axios.post(`${WAREHOUSE_API_URL}/products`, req.body, {
            headers: getApiHeaders(req),
            timeout: 30000
        });
        
        console.log('✅ Product created successfully');
        res.status(201).json({
            status: 'success',
            data: { product: response.data.product || response.data }
        });
    } catch (error) {
        console.error('❌ Failed to create product:', error.message);
        res.status(error.response?.status || 500).json({
            status: 'error',
            message: error.response?.data?.message || 'Бүтээгдэхүүн үүсгэхэд алдаа гарлаа'
        });
    }
});

// --- ORDER/SALES ROUTES ---
app.get('/api/orders', async (req, res) => {
    console.log('Fetching orders from Warehouse API...', req.query);
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 50;
    
    try {
        const response = await axios.get(`${WAREHOUSE_API_URL}/orders`, {
            headers: getApiHeaders(req),
            params: { page, limit },
            timeout: 30000
        });
        
        const orders = response.data.orders || response.data.data?.orders || [];
        const total = response.data.total || response.data.data?.total || orders.length;
        
        console.log(`✅ Successfully fetched ${orders.length} orders from Warehouse`);
        
        res.json({
            status: 'success',
            data: {
                orders: orders,
                pagination: {
                    page: page,
                    limit: limit,
                    total: total,
                    totalPages: Math.ceil(total / limit)
                }
            }
        });
    } catch (error) {
        console.error('❌ Failed to fetch orders:', error.message);
        res.status(error.response?.status || 500).json({
            status: 'error',
            message: error.response?.data?.message || 'Захиалга авахад алдаа гарлаа',
            data: {
                orders: [],
                pagination: { page: 1, limit: limit, total: 0, totalPages: 0 }
            }
        });
    }
});

app.post('/api/orders', async (req, res) => {
    console.log('Creating order in Warehouse API:', req.body);
    const { customerId, items, orderType, paymentMethod, deliveryDate, creditTermDays } = req.body;
    
    try {
        const orderData = {
            customerId: customerId,
            items: items || [],
            orderType: orderType || 'Store',
            paymentMethod: paymentMethod || 'Cash',
            deliveryDate: deliveryDate || null,
            creditTermDays: creditTermDays || null,
            orderDate: new Date().toISOString(),
            source: 'aguulga3'
        };
        
        const response = await axios.post(`${WAREHOUSE_API_URL}/orders`, orderData, {
            headers: getApiHeaders(req),
            timeout: 30000
        });
        
        console.log(`✅ Order created successfully`);
        
        res.status(201).json({
            status: 'success',
            data: {
                order: response.data.order || response.data
            }
        });
    } catch (error) {
        console.error('❌ Failed to create order:', error.message);
        res.status(error.response?.status || 500).json({
            status: 'error',
            message: error.response?.data?.message || 'Захиалга үүсгэхэд алдаа гарлаа'
        });
    }
});

// --- CUSTOMER ROUTES ---
app.get('/api/customers', async (req, res) => {
    console.log('Fetching customers from Warehouse API...', req.query);
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 200;
    
    try {
        const response = await axios.get(`${WAREHOUSE_API_URL}/customers`, {
            headers: getApiHeaders(req),
            params: { page, limit },
            timeout: 30000
        });
        
        const customers = response.data.customers || response.data.data?.customers || [];
        const total = response.data.total || response.data.data?.total || customers.length;
        
        console.log(`✅ Successfully fetched ${customers.length} customers from Warehouse`);
        
        res.json({
            status: 'success',
            data: {
                customers: customers,
                pagination: {
                    page: page,
                    limit: limit,
                    total: total,
                    totalPages: Math.ceil(total / limit)
                }
            }
        });
    } catch (error) {
        console.error('❌ Failed to fetch customers:', error.message);
        res.status(error.response?.status || 500).json({
            status: 'error',
            message: error.response?.data?.message || 'Харилцагч авахад алдаа гарлаа',
            data: {
                customers: [],
                pagination: { page: 1, limit: limit, total: 0, totalPages: 0 }
            }
        });
    }
});

app.post('/api/customers', async (req, res) => {
    console.log('Creating customer in Warehouse API:', req.body);
    
    try {
        const response = await axios.post(`${WAREHOUSE_API_URL}/customers`, req.body, {
            headers: getApiHeaders(req),
            timeout: 30000
        });
        
        console.log('✅ Customer created successfully');
        res.status(201).json({
            status: 'success',
            data: { customer: response.data.customer || response.data }
        });
    } catch (error) {
        console.error('❌ Failed to create customer:', error.message);
        res.status(error.response?.status || 500).json({
            status: 'error',
            message: error.response?.data?.message || 'Харилцагч үүсгэхэд алдаа гарлаа'
        });
    }
});

// Proxy endpoint for Opendatalab organization search
app.get('/api/opendatalab/organization/:reg', async (req, res) => {
    const regNumber = req.params.reg;
    console.log(`Searching for organization with reg number: ${regNumber}`);

    try {
        const apiUrl = `https://opendatalab.mn/api/search?q=${encodeURIComponent(regNumber)}`;
        
        const response = await axios.get(apiUrl, {
            headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
                'Accept': 'application/json'
            },
            timeout: 10000
        });

        if (response.data && response.data.data && response.data.data.length > 0) {
            const orgData = response.data.data[0];
            res.json(orgData);
        } else {
            res.status(404).json({
                error: true,
                message: 'Байгуулга олдсонгүй'
            });
        }
    } catch (error) {
        console.error('Proxy error:', error.message);
        
        const statusCode = error.response ? error.response.status : 500;
        const message = error.response && error.response.data 
            ? (typeof error.response.data === 'string' ? error.response.data : JSON.stringify(error.response.data)) 
            : error.message;

        res.status(statusCode).json({
            error: true,
            message: `Backend proxy error: ${message}`
        });
    }
});

// Health check endpoint
app.get('/', (req, res) => {
    res.json({
        status: 'running',
        message: 'Backend Proxy Server - Connected to Warehouse API',
        warehouseApiUrl: WAREHOUSE_API_URL
    });
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on port ${PORT} (all interfaces)`);
    console.log(`📡 Warehouse API URL: ${WAREHOUSE_API_URL}`);
    console.log(`🔑 API Key configured: ${WAREHOUSE_API_KEY ? 'Yes' : 'No'}`);
    console.log(`📱 Mobile access: http://192.168.1.6:${PORT}`);
});
