def render_order_confirmation(order_id, total_amount, items):
    """Render order confirmation email template"""

    items_html = ""
    for item in items:
        items_html += f"""
        <tr>
            <td style="padding: 10px; border-bottom: 1px solid #ddd;">{item.get('name', 'Product')}</td>
            <td style="padding: 10px; border-bottom: 1px solid #ddd; text-align: center;">{item.get('quantity', 1)}</td>
            <td style="padding: 10px; border-bottom: 1px solid #ddd; text-align: right;">${item.get('price', 0):.2f}</td>
        </tr>
        """

    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Order Confirmation</title>
    </head>
    <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background-color: #f8f9fa; padding: 20px; border-radius: 5px;">
            <h1 style="color: #007bff; margin-top: 0;">Order Confirmation</h1>

            <p>Thank you for your order!</p>

            <div style="background-color: white; padding: 15px; border-radius: 5px; margin: 20px 0;">
                <h2 style="color: #333; font-size: 18px;">Order Details</h2>
                <p><strong>Order ID:</strong> {order_id}</p>

                <table style="width: 100%; border-collapse: collapse; margin-top: 15px;">
                    <thead>
                        <tr style="background-color: #f8f9fa;">
                            <th style="padding: 10px; text-align: left; border-bottom: 2px solid #ddd;">Product</th>
                            <th style="padding: 10px; text-align: center; border-bottom: 2px solid #ddd;">Quantity</th>
                            <th style="padding: 10px; text-align: right; border-bottom: 2px solid #ddd;">Price</th>
                        </tr>
                    </thead>
                    <tbody>
                        {items_html}
                    </tbody>
                    <tfoot>
                        <tr>
                            <td colspan="2" style="padding: 15px; text-align: right; font-weight: bold;">Total:</td>
                            <td style="padding: 15px; text-align: right; font-weight: bold; font-size: 18px; color: #007bff;">${total_amount:.2f}</td>
                        </tr>
                    </tfoot>
                </table>
            </div>

            <div style="margin-top: 20px; padding: 15px; background-color: #fff3cd; border-left: 4px solid #ffc107; border-radius: 3px;">
                <p style="margin: 0;"><strong>Next Steps:</strong></p>
                <ul style="margin: 10px 0;">
                    <li>Your order will be processed within 24 hours</li>
                    <li>You'll receive a shipping confirmation once your order is dispatched</li>
                    <li>Track your order anytime in your account dashboard</li>
                </ul>
            </div>

            <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; text-align: center; color: #666; font-size: 12px;">
                <p>This is an automated email. Please do not reply.</p>
                <p>If you have any questions, contact our support team.</p>
                <p>&copy; 2024 E-Commerce Platform. All rights reserved.</p>
            </div>
        </div>
    </body>
    </html>
    """

    return html
