# Frontend Application

The microservices backend is fully functional and ready to use! You can build a frontend application in any framework.

## Options for Frontend

### Option 1: Build Your Own (Recommended for Learning)

Build a custom frontend using:
- **React** (with Vite or Create React App)
- **Vue.js** (with Nuxt or Vue CLI)
- **Angular**
- **Next.js** (React with SSR)
- **Svelte/SvelteKit**
- **Plain HTML/CSS/JavaScript**

### Option 2: Use API Testing Tools

Test the backend directly:
- **Postman** - API testing and documentation
- **Insomnia** - REST client
- **cURL** - Command-line testing (see [API_EXAMPLES.md](../docs/API_EXAMPLES.md))
- **HTTPie** - User-friendly HTTP client

### Option 3: Simple HTML Frontend

Create a basic single-page application with vanilla JavaScript:

```html
<!DOCTYPE html>
<html>
<head>
    <title>E-Commerce</title>
</head>
<body>
    <div id="app">
        <h1>E-Commerce Platform</h1>
        <!-- Your UI here -->
    </div>

    <script>
        const API_BASE_URL = 'http://localhost:8080/api';
        let token = localStorage.getItem('token');

        // Example: Login
        async function login(email, password) {
            const response = await fetch(`${API_BASE_URL}/users/login`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email, password })
            });
            const data = await response.json();
            token = data.token;
            localStorage.setItem('token', token);
        }

        // Example: Get Products
        async function getProducts() {
            const response = await fetch(`${API_BASE_URL}/products`);
            const data = await response.json();
            console.log(data);
        }

        // Example: Add to Cart
        async function addToCart(productId, quantity) {
            const response = await fetch(`${API_BASE_URL}/cart/items`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${token}`
                },
                body: JSON.stringify({ productId, quantity })
            });
            const data = await response.json();
            console.log(data);
        }
    </script>
</body>
</html>
```

## React Frontend Quickstart

If you want to build with React:

```bash
# Create React app
npm create vite@latest customer-app -- --template react
cd customer-app

# Install dependencies
npm install axios react-router-dom

# Install Tailwind CSS (optional)
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p
```

### Sample React Component

```jsx
import { useState, useEffect } from 'react';
import axios from 'axios';

const API_URL = 'http://localhost:8080/api';

function ProductList() {
    const [products, setProducts] = useState([]);

    useEffect(() => {
        axios.get(`${API_URL}/products`)
            .then(res => setProducts(res.data.products || res.data))
            .catch(err => console.error(err));
    }, []);

    return (
        <div className="product-list">
            {products.map(product => (
                <div key={product.id} className="product-card">
                    <h3>{product.name}</h3>
                    <p>{product.description}</p>
                    <p>${product.price}</p>
                    <button>Add to Cart</button>
                </div>
            ))}
        </div>
    );
}

export default ProductList;
```

## Required Features for E-Commerce Frontend

### Pages to Build

1. **Home Page** - Featured products, categories
2. **Product Listing** - Search, filter, pagination
3. **Product Detail** - Images, description, reviews
4. **Shopping Cart** - View, update, remove items
5. **Checkout** - Shipping address form
6. **Payment** - Razorpay integration
7. **Order Confirmation** - Success message, order details
8. **User Dashboard** - Profile, order history
9. **Login/Register** - Authentication forms

### Key Integrations

#### Authentication

```javascript
// Login
const login = async (email, password) => {
    const response = await axios.post(`${API_URL}/users/login`, {
        email,
        password
    });
    localStorage.setItem('token', response.data.token);
    return response.data;
};

// Use token in requests
axios.defaults.headers.common['Authorization'] = `Bearer ${token}`;
```

#### Razorpay Integration

```javascript
// Load Razorpay script
<script src="https://checkout.razorpay.com/v1/checkout.js"></script>

// Payment handler
const handlePayment = async (orderData) => {
    // Create payment order
    const { data } = await axios.post(`${API_URL}/payments/create-order`, {
        order_id: orderData.id,
        amount: orderData.total_amount
    });

    // Razorpay checkout
    const options = {
        key: data.key_id,
        amount: data.amount * 100,
        currency: data.currency,
        name: 'E-Commerce Platform',
        order_id: data.razorpay_order_id,
        handler: async function (response) {
            // Verify payment
            await axios.post(`${API_URL}/payments/verify`, {
                razorpay_order_id: response.razorpay_order_id,
                razorpay_payment_id: response.razorpay_payment_id,
                razorpay_signature: response.razorpay_signature
            });
            // Show success message
        }
    };

    const rzp = new window.Razorpay(options);
    rzp.open();
};
```

## API Endpoints Reference

See [API_EXAMPLES.md](../docs/API_EXAMPLES.md) for complete API documentation.

### Quick Reference

- `POST /api/users/register` - Register user
- `POST /api/users/login` - Login
- `GET /api/products` - List products
- `POST /api/cart/items` - Add to cart
- `POST /api/orders` - Create order
- `POST /api/payments/create-order` - Initiate payment

## State Management Recommendations

For React:
- **Context API** - Simple state (auth, cart)
- **Redux Toolkit** - Complex state management
- **Zustand** - Lightweight alternative
- **React Query** - Server state management

For Vue:
- **Pinia** - Official state management
- **Vuex** - Legacy option

## Styling Options

- **Tailwind CSS** - Utility-first CSS
- **Material-UI** - React components
- **Chakra UI** - Accessible components
- **Bootstrap** - Traditional framework
- **Custom CSS** - Full control

## Development Tips

1. **Use Axios Interceptors** - Handle authentication automatically
2. **Error Handling** - Show user-friendly error messages
3. **Loading States** - Display spinners while fetching data
4. **Form Validation** - Validate inputs before sending
5. **Responsive Design** - Mobile-first approach
6. **Toast Notifications** - User feedback for actions

## Example Projects to Reference

- [e-commerce-react](https://github.com/safak/youtube)
- [react-shopping-cart](https://github.com/jeffersonRibeiro/react-shopping-cart)
- [vue-storefront](https://github.com/vuestorefront/vue-storefront)

## Testing Your Frontend

```bash
# Start backend services
docker-compose up

# In another terminal, start your frontend
cd customer-app
npm run dev
```

Access at http://localhost:5173 (Vite default) or http://localhost:3000 (CRA default)

## CORS Configuration

The backend is configured to accept requests from any origin (for development). In production, update CORS settings in each service.

## Next Steps

1. Choose your frontend framework
2. Set up project structure
3. Implement authentication first
4. Build product browsing
5. Add cart functionality
6. Integrate payment gateway
7. Test complete user flow

## Learning Resources

- [React Documentation](https://react.dev)
- [Vue.js Guide](https://vuejs.org/guide/)
- [Tailwind CSS Docs](https://tailwindcss.com/docs)
- [Razorpay Checkout Docs](https://razorpay.com/docs/payments/payment-gateway/web-integration/)

## Support

For API issues, check the backend service logs:
```bash
docker-compose logs -f service-name
```

Happy building! 🎨
