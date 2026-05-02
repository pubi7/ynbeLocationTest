const express = require('express');
const cors = require('cors');
const axios = require('axios');
const {
    computeDeliveryDateForWeb,
    getRoleFromRequest,
} = require('./weve_order_schedule');

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
    const limit = req.query.limit === 'all' ? 'all' : (parseInt(req.query.limit) || 50);

    try {
        const response = await axios.get(`${WAREHOUSE_API_URL}/orders`, {
            headers: getApiHeaders(req),
            params: { ...req.query, page, limit },
            timeout: 30000
        });
        
        const data = response.data.data || response.data;
        const orders = data.orders || response.data.orders || [];
        const pagination = data.pagination || {};
        const total = pagination.total ?? response.data.total ?? orders.length;
        const totalPages = limit === 'all' ? 1 : Math.ceil(total / (Number(limit) || 1));

        console.log(`✅ Successfully fetched ${orders.length} orders from Warehouse`);

        res.json({
            status: 'success',
            data: {
                orders: orders,
                pagination: {
                    page: pagination.page ?? page,
                    limit: pagination.limit ?? limit,
                    total: total,
                    totalPages: totalPages
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

/** Мобайлын items → warehouse: тоо бүтэн бүхэл, үнэгүйг алдахгүй; зарим Prisma snake_case уншдаг тул талбар хувилна. */
function normalizeOrderItemsForWarehouse(items) {
    if (!Array.isArray(items)) return [];
    return items.map((row) => {
        if (!row || typeof row !== 'object') return row;
        const r = { ...row };
        if (r.quantity != null) {
            r.quantity = Math.max(0, Math.floor(Number(r.quantity)) || 0);
        }
        const fqRaw = r.freeQuantity;
        r.freeQuantity =
            fqRaw == null || fqRaw === ''
                ? 0
                : Math.max(0, Math.floor(Number(fqRaw)) || 0);
        if (r.paidQuantity != null && r.paidQuantity !== '') {
            r.paidQuantity = Math.max(0, Math.floor(Number(r.paidQuantity)) || 0);
        }
        const q = r.quantity != null ? Math.max(0, Math.floor(Number(r.quantity)) || 0) : 0;
        const fq = r.freeQuantity;
        const pq =
            r.paidQuantity != null && r.paidQuantity !== ''
                ? Math.max(0, Math.floor(Number(r.paidQuantity)) || 0)
                : null;
        // Үлдэгдэл хасах нийт: эхлээд client-ийн totalPiecesForStock; үгүй бол wire-ийг ялгана.
        // Алдааны мессеж гардаггүй — буруу тооцоолол зөвхөн буруу totalPiecesForStock өгнө (warehouse талд илэрнэ).
        let tps = r.totalPiecesForStock;
        if (tps != null && tps !== '') {
            r.totalPiecesForStock = Math.max(0, Math.floor(Number(tps)) || 0);
        } else if (fq <= 0) {
            r.totalPiecesForStock = q;
        } else if (pq != null && pq < q) {
            // Хуучин: quantity = нийт физик (төлөх+үнэгүй), paidQuantity < quantity.
            r.totalPiecesForStock = q;
        } else if (pq != null && pq === q) {
            // Шинэ: quantity = төлөх = paidQuantity, үнэгүй тусад → нийт = q + fq.
            r.totalPiecesForStock = q + fq;
        } else if (pq == null && q > fq) {
            // paidQuantity ирээгүй, quantity нь үнэгүйгээс их → нийт нь q гэж үзнэ.
            r.totalPiecesForStock = q;
        } else if (pq == null && q <= fq && q === fq && q >= 2) {
            // quantity == free (ж: 2=2) — нийт физик q, q+fq биш (давхар тоолохгүй).
            r.totalPiecesForStock = q;
        } else if (pq == null && fq > 0) {
            // Ж: paidQuantity алдсан шинэ мөр q=1 fq=1.
            r.totalPiecesForStock = q + fq;
        } else {
            r.totalPiecesForStock = q;
        }
        r.total_pieces_for_stock = r.totalPiecesForStock;
        r.free_quantity = r.freeQuantity;
        if (r.paidQuantity != null) r.paid_quantity = r.paidQuantity;
        if (r.productId != null) r.product_id = r.productId;
        if (r.unitPrice != null) r.unit_price = r.unitPrice;
        if (r.lineTotal != null) r.line_total = r.lineTotal;
        if (r.priceMode != null) r.price_mode = r.priceMode;
        return r;
    });
}

app.post('/api/orders', async (req, res) => {
    console.log('Creating order in Warehouse API:', req.body);
    const {
        customerId,
        items,
        orderType,
        paymentMethod,
        deliveryDate,
        creditTermDays,
        allowInsufficientStock,
        notes,
        userWeveToken,
    } = req.body;
    
    try {
        // Mobile: хүргэлтийн өдөр = сервер дээр захиалга авсан өдөр (orderDate-ийн өдөр).
        // deliveryDate ирсэн ч гэсэн нэг мөр логик: orderDate өдөртэй тэнцүү болгоно.
        const orderDateIso = new Date().toISOString();
        const receivedDay = orderDateIso.slice(0, 10); // YYYY-MM-DD
        const computedDeliveryDate = receivedDay;

        const orderData = {
            customerId: customerId,
            items: normalizeOrderItemsForWarehouse(items || []),
            orderType: orderType || 'Store',
            paymentMethod: paymentMethod || 'Cash',
            deliveryDate: computedDeliveryDate || null,
            creditTermDays: creditTermDays || null,
            orderDate: orderDateIso,
            source: 'aguulga3',
            allowInsufficientStock: allowInsufficientStock === true,
            ...(typeof notes === 'string' && notes.trim() !== '' ? { notes: notes.trim() } : {}),
            ...(typeof userWeveToken === 'string' && userWeveToken.trim() !== ''
                ? { userWeveToken: userWeveToken.trim() }
                : {}),
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
            params: { ...req.query, page, limit },
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

// --- AGENTS LOCATION (гар утасны байршил → Weve website) ---
app.post('/api/agents/:id/location', async (req, res) => {
    const agentId = req.params.id;
    const { latitude, longitude, ipAddress, accuracy } = req.body;
    try {
        const response = await axios.post(
            `${WAREHOUSE_API_URL}/agents/${agentId}/location`,
            { latitude, longitude, ipAddress, accuracy },
            { headers: getApiHeaders(req), timeout: 10000 }
        );
        res.status(response.status || 201).json(response.data);
    } catch (error) {
        const status = error.response?.status || 500;
        const msg = error.response?.data?.message || 'Байршил илгээхэд алдаа';
        res.status(status).json({ status: 'error', message: msg });
    }
});

app.get('/api/agents/locations/all', async (req, res) => {
    try {
        const response = await axios.get(
            `${WAREHOUSE_API_URL}/agents/locations/all`,
            { headers: getApiHeaders(req), params: req.query, timeout: 15000 }
        );
        res.json(response.data);
    } catch (error) {
        const status = error.response?.status || 500;
        const msg = error.response?.data?.message || 'Байршил татахад алдаа';
        res.status(status).json({ status: 'error', message: msg });
    }
});

// --- EBARIMT TIN INFO ---
// Register дугаараас TIN авах - st-api (туршилт), api (бодит)
const EBARIMT_GETTININFO_URL = process.env.EBARIMT_GETTININFO_URL || 'https://st-api.ebarimt.mn/api/info/check/getTinInfo';
app.get('/api/ebarimt/getTinInfo', async (req, res) => {
    const regNo = req.query.regNo;
    if (!regNo || String(regNo).trim() === '') {
        return res.status(400).json({
            success: false,
            message: 'Регистрийн дугаар (regNo) шаардлагатай'
        });
    }

    try {
        const apiUrl = `${EBARIMT_GETTININFO_URL}?regNo=${encodeURIComponent(regNo)}`;
        console.log(`📡 Ebarimt getTinInfo: ${apiUrl}`);

        const response = await axios.get(apiUrl, {
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'User-Agent': 'Aguulga-Mobile/1.0'
            },
            timeout: 15000
        });

        if (response.data) {
            const api = response.data;
            // api.ebarimt.mn: { msg: "Амжилттай", status: 200, data: 76000822749 }
            // data нь TIN дугаар шууд (тоо)
            const dataVal = api?.data;
            const success = api?.status === 200 || api?.msg === 'Амжилттай';
            let tin = '';
            let name = '';

            if (success && (typeof dataVal === 'number' || typeof dataVal === 'string')) {
                tin = String(dataVal).trim();
            } else if (success && dataVal && typeof dataVal === 'object') {
                tin = String(dataVal.tin ?? dataVal.TIN ?? dataVal.tinNumber ?? dataVal.taxId ?? '').trim();
                name = String(dataVal.name ?? dataVal.companyName ?? dataVal.orgName ?? '').trim();
            }
            if (tin === regNo) tin = '';

            console.log(`✅ getTinInfo: regNo=${regNo} → tin=${tin || '(олдсонгүй)'}`);
            res.json({
                success: true,
                tin: tin,
                name: name,
                regNo: String(regNo)
            });
        } else {
            res.status(404).json({
                success: false,
                message: 'Бүртгэл олдсонгүй'
            });
        }
    } catch (error) {
        console.error('❌ getTinInfo proxy error:', error.message);
        const statusCode = error.response?.status ?? 500;
        const msg = error.response?.data?.message ?? error.response?.data?.error ?? error.message;
        res.status(statusCode).json({
            success: false,
            message: msg || 'TIN авахад алдаа гарлаа'
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
