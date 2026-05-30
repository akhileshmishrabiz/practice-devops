package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type OrderStatus string

const (
	OrderStatusPending         OrderStatus = "pending"
	OrderStatusPaymentPending  OrderStatus = "payment_pending"
	OrderStatusConfirmed       OrderStatus = "confirmed"
	OrderStatusProcessing      OrderStatus = "processing"
	OrderStatusShipped         OrderStatus = "shipped"
	OrderStatusDelivered       OrderStatus = "delivered"
	OrderStatusCancelled       OrderStatus = "cancelled"
)

type Order struct {
	ID              string      `gorm:"primaryKey;type:uuid" json:"id"`
	UserID          string      `gorm:"type:uuid;not null;index" json:"user_id"`
	UserEmail       string      `gorm:"size:255;not null" json:"user_email"`
	Status          OrderStatus `gorm:"size:50;not null;index;default:'pending'" json:"status"`
	TotalAmount     float64     `gorm:"not null" json:"total_amount"`
	Tax             float64     `gorm:"not null;default:0" json:"tax"`
	ShippingAddress string      `gorm:"type:text" json:"shipping_address"`
	City            string      `gorm:"size:100" json:"city"`
	State           string      `gorm:"size:100" json:"state"`
	ZipCode         string      `gorm:"size:20" json:"zip_code"`
	Country         string      `gorm:"size:100" json:"country"`
	Items           []OrderItem `gorm:"foreignKey:OrderID;constraint:OnDelete:CASCADE" json:"items"`
	CreatedAt       time.Time   `json:"created_at"`
	UpdatedAt       time.Time   `json:"updated_at"`
}

type OrderItem struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	OrderID   string    `gorm:"type:uuid;not null;index" json:"order_id"`
	ProductID int       `gorm:"not null" json:"product_id"`
	Name      string    `gorm:"size:255;not null" json:"name"`
	Price     float64   `gorm:"not null" json:"price"`
	Quantity  int       `gorm:"not null" json:"quantity"`
	Subtotal  float64   `gorm:"not null" json:"subtotal"`
	CreatedAt time.Time `json:"created_at"`
}

func (order *Order) BeforeCreate(tx *gorm.DB) error {
	if order.ID == "" {
		order.ID = uuid.New().String()
	}
	return nil
}

func (Order) TableName() string {
	return "orders"
}

func (OrderItem) TableName() string {
	return "order_items"
}

type CreateOrderRequest struct {
	ShippingAddress string `json:"shipping_address" binding:"required"`
	City            string `json:"city" binding:"required"`
	State           string `json:"state" binding:"required"`
	ZipCode         string `json:"zip_code" binding:"required"`
	Country         string `json:"country" binding:"required"`
}

type UpdateOrderStatusRequest struct {
	Status OrderStatus `json:"status" binding:"required"`
}
