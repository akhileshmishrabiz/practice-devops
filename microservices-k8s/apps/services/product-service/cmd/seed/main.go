package main

import (
	"fmt"
	"product-service/config"
	"product-service/database"
	"product-service/models"

	log "github.com/sirupsen/logrus"
)

func main() {
	log.Info("Starting database seed...")

	// Load configuration
	cfg := config.LoadConfig()

	// Connect to database
	db := database.Connect(cfg)

	// Clear existing products (for development only)
	db.Exec("TRUNCATE TABLE products RESTART IDENTITY CASCADE")

	// Sample products
	products := []models.Product{
		{
			Name:        "iPhone 14 Pro",
			Description: "Latest Apple iPhone with A16 Bionic chip, 6.1-inch Super Retina XDR display, and Pro camera system",
			Price:       999.99,
			Stock:       50,
			Category:    "Electronics",
			ImageURL:    "https://example.com/images/iphone14pro.jpg",
			Images:      []string{"https://example.com/images/iphone14pro-1.jpg", "https://example.com/images/iphone14pro-2.jpg"},
			SKU:         "ELEC-IPH-001",
			IsActive:    true,
		},
		{
			Name:        "Samsung Galaxy S23 Ultra",
			Description: "Premium Android smartphone with 200MP camera, S Pen, and 5000mAh battery",
			Price:       1199.99,
			Stock:       35,
			Category:    "Electronics",
			ImageURL:    "https://example.com/images/galaxys23.jpg",
			Images:      []string{"https://example.com/images/galaxys23-1.jpg"},
			SKU:         "ELEC-SAM-001",
			IsActive:    true,
		},
		{
			Name:        "MacBook Pro 16-inch",
			Description: "Apple M2 Pro chip, 16GB RAM, 512GB SSD, stunning Liquid Retina XDR display",
			Price:       2499.99,
			Stock:       20,
			Category:    "Electronics",
			ImageURL:    "https://example.com/images/macbookpro.jpg",
			Images:      []string{"https://example.com/images/macbookpro-1.jpg", "https://example.com/images/macbookpro-2.jpg"},
			SKU:         "ELEC-MAC-001",
			IsActive:    true,
		},
		{
			Name:        "Sony WH-1000XM5 Headphones",
			Description: "Industry-leading noise canceling wireless headphones with premium sound quality",
			Price:       399.99,
			Stock:       75,
			Category:    "Electronics",
			ImageURL:    "https://example.com/images/sonywh1000xm5.jpg",
			Images:      []string{"https://example.com/images/sonywh1000xm5-1.jpg"},
			SKU:         "ELEC-SON-001",
			IsActive:    true,
		},
		{
			Name:        "iPad Air 5th Gen",
			Description: "10.9-inch Liquid Retina display, M1 chip, 256GB storage, works with Apple Pencil",
			Price:       749.99,
			Stock:       40,
			Category:    "Electronics",
			ImageURL:    "https://example.com/images/ipadair.jpg",
			Images:      []string{"https://example.com/images/ipadair-1.jpg"},
			SKU:         "ELEC-IPA-001",
			IsActive:    true,
		},
		{
			Name:        "Nike Air Max 270",
			Description: "Men's running shoes with Max Air unit for all-day comfort",
			Price:       150.00,
			Stock:       100,
			Category:    "Footwear",
			ImageURL:    "https://example.com/images/nikeairmax.jpg",
			Images:      []string{"https://example.com/images/nikeairmax-1.jpg", "https://example.com/images/nikeairmax-2.jpg"},
			SKU:         "FOOT-NIK-001",
			IsActive:    true,
		},
		{
			Name:        "Adidas Ultraboost 22",
			Description: "Premium running shoes with Boost cushioning and Primeknit upper",
			Price:       180.00,
			Stock:       85,
			Category:    "Footwear",
			ImageURL:    "https://example.com/images/ultraboost.jpg",
			Images:      []string{"https://example.com/images/ultraboost-1.jpg"},
			SKU:         "FOOT-ADI-001",
			IsActive:    true,
		},
		{
			Name:        "Levi's 501 Original Jeans",
			Description: "Classic straight fit jeans, the original blue jean since 1873",
			Price:       69.99,
			Stock:       120,
			Category:    "Clothing",
			ImageURL:    "https://example.com/images/levis501.jpg",
			Images:      []string{"https://example.com/images/levis501-1.jpg"},
			SKU:         "CLOT-LEV-001",
			IsActive:    true,
		},
		{
			Name:        "The North Face Hoodie",
			Description: "Comfortable pullover hoodie made with soft cotton blend fleece",
			Price:       75.00,
			Stock:       90,
			Category:    "Clothing",
			ImageURL:    "https://example.com/images/tnfhoodie.jpg",
			Images:      []string{"https://example.com/images/tnfhoodie-1.jpg"},
			SKU:         "CLOT-TNF-001",
			IsActive:    true,
		},
		{
			Name:        "Ray-Ban Aviator Sunglasses",
			Description: "Classic aviator style sunglasses with polarized lenses",
			Price:       154.00,
			Stock:       60,
			Category:    "Accessories",
			ImageURL:    "https://example.com/images/rayban.jpg",
			Images:      []string{"https://example.com/images/rayban-1.jpg"},
			SKU:         "ACCS-RAY-001",
			IsActive:    true,
		},
		{
			Name:        "Fossil Gen 6 Smartwatch",
			Description: "Touchscreen smartwatch with heart rate tracking and GPS",
			Price:       299.00,
			Stock:       45,
			Category:    "Accessories",
			ImageURL:    "https://example.com/images/fossilgen6.jpg",
			Images:      []string{"https://example.com/images/fossilgen6-1.jpg"},
			SKU:         "ACCS-FOS-001",
			IsActive:    true,
		},
		{
			Name:        "Instant Pot Duo 7-in-1",
			Description: "Electric pressure cooker, slow cooker, rice cooker, and more in one appliance",
			Price:       89.99,
			Stock:       55,
			Category:    "Home & Kitchen",
			ImageURL:    "https://example.com/images/instantpot.jpg",
			Images:      []string{"https://example.com/images/instantpot-1.jpg"},
			SKU:         "HOME-INS-001",
			IsActive:    true,
		},
		{
			Name:        "Dyson V15 Detect Vacuum",
			Description: "Cordless vacuum with laser dust detection and powerful suction",
			Price:       649.99,
			Stock:       25,
			Category:    "Home & Kitchen",
			ImageURL:    "https://example.com/images/dysonv15.jpg",
			Images:      []string{"https://example.com/images/dysonv15-1.jpg"},
			SKU:         "HOME-DYS-001",
			IsActive:    true,
		},
		{
			Name:        "KitchenAid Stand Mixer",
			Description: "5-quart tilt-head stand mixer in Empire Red, 10 speeds",
			Price:       379.99,
			Stock:       30,
			Category:    "Home & Kitchen",
			ImageURL:    "https://example.com/images/kitchenaid.jpg",
			Images:      []string{"https://example.com/images/kitchenaid-1.jpg"},
			SKU:         "HOME-KIT-001",
			IsActive:    true,
		},
		{
			Name:        "Philips Hue Starter Kit",
			Description: "Smart LED light bulbs with hub, works with Alexa and Google Home",
			Price:       199.99,
			Stock:       65,
			Category:    "Home & Kitchen",
			ImageURL:    "https://example.com/images/philipshue.jpg",
			Images:      []string{"https://example.com/images/philipshue-1.jpg"},
			SKU:         "HOME-PHI-001",
			IsActive:    true,
		},
		{
			Name:        "Bestseller Novel Collection",
			Description: "Set of 5 bestselling fiction novels from renowned authors",
			Price:       49.99,
			Stock:       80,
			Category:    "Books",
			ImageURL:    "https://example.com/images/novelset.jpg",
			Images:      []string{"https://example.com/images/novelset-1.jpg"},
			SKU:         "BOOK-NOV-001",
			IsActive:    true,
		},
		{
			Name:        "Learning Python 5th Edition",
			Description: "Comprehensive guide to Python programming for beginners and experts",
			Price:       54.99,
			Stock:       70,
			Category:    "Books",
			ImageURL:    "https://example.com/images/learningpython.jpg",
			Images:      []string{"https://example.com/images/learningpython-1.jpg"},
			SKU:         "BOOK-PYT-001",
			IsActive:    true,
		},
		{
			Name:        "Nintendo Switch OLED",
			Description: "Gaming console with 7-inch OLED screen, enhanced audio, and 64GB storage",
			Price:       349.99,
			Stock:       40,
			Category:    "Gaming",
			ImageURL:    "https://example.com/images/switcholed.jpg",
			Images:      []string{"https://example.com/images/switcholed-1.jpg", "https://example.com/images/switcholed-2.jpg"},
			SKU:         "GAME-NIN-001",
			IsActive:    true,
		},
		{
			Name:        "PlayStation 5",
			Description: "Next-gen gaming console with ultra-high-speed SSD and 4K gaming",
			Price:       499.99,
			Stock:       15,
			Category:    "Gaming",
			ImageURL:    "https://example.com/images/ps5.jpg",
			Images:      []string{"https://example.com/images/ps5-1.jpg"},
			SKU:         "GAME-SON-001",
			IsActive:    true,
		},
		{
			Name:        "Logitech G Pro Keyboard",
			Description: "Mechanical gaming keyboard with customizable RGB lighting",
			Price:       129.99,
			Stock:       50,
			Category:    "Gaming",
			ImageURL:    "https://example.com/images/logitechgpro.jpg",
			Images:      []string{"https://example.com/images/logitechgpro-1.jpg"},
			SKU:         "GAME-LOG-001",
			IsActive:    true,
		},
		{
			Name:        "Yoga Mat Pro",
			Description: "Premium non-slip yoga mat, 6mm thick, eco-friendly material",
			Price:       39.99,
			Stock:       95,
			Category:    "Sports",
			ImageURL:    "https://example.com/images/yogamat.jpg",
			Images:      []string{"https://example.com/images/yogamat-1.jpg"},
			SKU:         "SPRT-YOG-001",
			IsActive:    true,
		},
		{
			Name:        "Resistance Bands Set",
			Description: "5-piece resistance band set with different resistance levels",
			Price:       29.99,
			Stock:       110,
			Category:    "Sports",
			ImageURL:    "https://example.com/images/resistancebands.jpg",
			Images:      []string{"https://example.com/images/resistancebands-1.jpg"},
			SKU:         "SPRT-RES-001",
			IsActive:    true,
		},
		{
			Name:        "Wilson Basketball",
			Description: "Official size basketball with superior grip and durability",
			Price:       24.99,
			Stock:       75,
			Category:    "Sports",
			ImageURL:    "https://example.com/images/wilsonball.jpg",
			Images:      []string{"https://example.com/images/wilsonball-1.jpg"},
			SKU:         "SPRT-WIL-001",
			IsActive:    true,
		},
		{
			Name:        "YETI Rambler Tumbler",
			Description: "30 oz stainless steel insulated tumbler, keeps drinks cold for 24 hours",
			Price:       34.99,
			Stock:       85,
			Category:    "Outdoor",
			ImageURL:    "https://example.com/images/yetirambler.jpg",
			Images:      []string{"https://example.com/images/yetirambler-1.jpg"},
			SKU:         "OUTD-YET-001",
			IsActive:    true,
		},
		{
			Name:        "Coleman Camping Tent",
			Description: "4-person camping tent with WeatherTec system, easy setup",
			Price:       139.99,
			Stock:       35,
			Category:    "Outdoor",
			ImageURL:    "https://example.com/images/colemantent.jpg",
			Images:      []string{"https://example.com/images/colemantent-1.jpg"},
			SKU:         "OUTD-COL-001",
			IsActive:    true,
		},
	}

	// Insert products
	for _, product := range products {
		if err := db.Create(&product).Error; err != nil {
			log.WithError(err).Errorf("Failed to create product: %s", product.Name)
		} else {
			log.WithField("product", product.Name).Info("Product created successfully")
		}
	}

	fmt.Printf("\n✅ Successfully seeded %d products\n", len(products))
}
