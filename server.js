const express = require('express');
const cors = require('cors');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// --- MOCK DATA START ---
// Mock User Database
const MOCK_USER = {
    id: 1,
    name: 'Admin User',
    email: 'admin@admin.com',
    role: 'admin',
    companyId: 1
};

const MOCK_TOKEN = 'mock-jwt-token-12345';

// Mock Products
const MOCK_PRODUCTS = [
    { id: 1, nameMongolian: 'Талх', nameEnglish: 'Bread', priceRetail: 2500, priceWholesale: 2200, description: 'Өдөр тутмын талх', category: { nameMongolian: 'Хүнс' } },
    { id: 2, nameMongolian: 'Сүү', nameEnglish: 'Milk', priceRetail: 3500, priceWholesale: 3200, description: 'Үнээний сүү', category: { nameMongolian: 'Хүнс' } },
    { id: 3, nameMongolian: 'Өндөг', nameEnglish: 'Egg', priceRetail: 500, priceWholesale: 450, description: 'Шинэ өндөг', category: { nameMongolian: 'Хүнс' } },
    { id: 4, nameMongolian: 'Ундаа', nameEnglish: 'Soda', priceRetail: 1500, priceWholesale: 1200, description: 'Хийжүүлсэн ундаа', category: { nameMongolian: 'Ундаа' } }
];

// Mock Orders/Sales
const MOCK_ORDERS = [];

// Mock Customers
const MOCK_CUSTOMERS = [
    { id: 1, name: 'Дэлгүүр 1', locationLatitude: 47.9188, locationLongitude: 106.9176 },
    { id: 2, name: 'Супермаркет', locationLatitude: 47.9200, locationLongitude: 106.9200 }
];

// --- AUTH ROUTES ---
app.post('/api/auth/login', (req, res) => {
    const { identifier, password } = req.body;
    console.log('Login attempt:', identifier);

    // Simple mock login (accept admin@admin.com or any email with password 'password')
    if ((identifier === 'admin@admin.com' && password === 'password') || password === 'password') {
        res.json({
            status: 'success',
            data: {
                user: { ...MOCK_USER, email: identifier },
                token: MOCK_TOKEN
            }
        });
    } else {
        res.status(401).json({
            status: 'error',
            message: 'Имэйл эсвэл нууц үг буруу байна (Test: admin@admin.com / password)'
        });
    }
});

// --- PRODUCT ROUTES ---
app.get('/api/products', (req, res) => {
    console.log('Fetching products...');
    res.json({
        status: 'success',
        data: {
            products: MOCK_PRODUCTS
        }
    });
});

app.post('/api/products', (req, res) => {
    console.log('Adding product:', req.body);
    const newProduct = { 
        id: MOCK_PRODUCTS.length + 1, 
        ...req.body,
        category: { nameMongolian: 'Бусад' } 
    };
    MOCK_PRODUCTS.push(newProduct);
    res.status(201).json({
        status: 'success',
        data: { product: newProduct }
    });
});

// --- ORDER/SALES ROUTES ---
app.get('/api/orders', (req, res) => {
    console.log('Fetching orders...');
    res.json({
        status: 'success',
        data: {
            orders: MOCK_ORDERS
        }
    });
});

app.post('/api/orders', (req, res) => {
    console.log('Creating order:', req.body);
    const newOrder = { 
        id: Date.now(), 
        createdAt: new Date().toISOString(),
        ...req.body,
        createdById: MOCK_USER.id,
        createdBy: MOCK_USER,
        totalAmount: 10000 // Mock amount calculation
    };
    MOCK_ORDERS.push(newOrder);
    res.status(201).json({
        status: 'success',
        data: newOrder
    });
});

// --- CUSTOMER ROUTES ---
app.get('/api/customers', (req, res) => {
    res.json({
        status: 'success',
        data: {
            customers: MOCK_CUSTOMERS
        }
    });
});

// --- MOCK DATA END ---

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
    res.send('Backend Proxy Server is running (with Mocks)');
});

app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});
