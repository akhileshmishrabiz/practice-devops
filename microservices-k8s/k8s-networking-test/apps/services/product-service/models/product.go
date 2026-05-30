package models

import (
	"time"

	"gorm.io/gorm"
)

type Product struct {
	ID          uint           `gorm:"primaryKey" json:"id"`
	Name        string         `gorm:"size:255;not null;index" json:"name" binding:"required"`
	Description string         `gorm:"type:text" json:"description"`
	Price       float64        `gorm:"not null;index" json:"price" binding:"required,gt=0"`
	Stock       int            `gorm:"not null;default:0" json:"stock" binding:"gte=0"`
	Category    string         `gorm:"size:100;not null;index" json:"category" binding:"required"`
	ImageURL    string         `gorm:"size:500" json:"image_url"`
	Images      []string       `gorm:"type:text[]" json:"images"`
	SKU         string         `gorm:"size:100;unique;index" json:"sku"`
	IsActive    bool           `gorm:"default:true;index" json:"is_active"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

// TableName specifies the table name for the Product model
func (Product) TableName() string {
	return "products"
}

// ProductCreateRequest is the request payload for creating a product
type ProductCreateRequest struct {
	Name        string   `json:"name" binding:"required"`
	Description string   `json:"description"`
	Price       float64  `json:"price" binding:"required,gt=0"`
	Stock       int      `json:"stock" binding:"gte=0"`
	Category    string   `json:"category" binding:"required"`
	ImageURL    string   `json:"image_url"`
	Images      []string `json:"images"`
	SKU         string   `json:"sku"`
}

// ProductUpdateRequest is the request payload for updating a product
type ProductUpdateRequest struct {
	Name        *string   `json:"name"`
	Description *string   `json:"description"`
	Price       *float64  `json:"price" binding:"omitempty,gt=0"`
	Stock       *int      `json:"stock" binding:"omitempty,gte=0"`
	Category    *string   `json:"category"`
	ImageURL    *string   `json:"image_url"`
	Images      *[]string `json:"images"`
	SKU         *string   `json:"sku"`
	IsActive    *bool     `json:"is_active"`
}

// StockUpdateRequest is for updating product stock
type StockUpdateRequest struct {
	Quantity int    `json:"quantity" binding:"required"`
	Action   string `json:"action" binding:"required,oneof=add subtract set"`
}
