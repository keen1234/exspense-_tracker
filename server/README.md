# Receipt Scanner API

A standalone Dart server that uses Google ML Kit to scan and parse receipts.

## Setup

```bash
cd server
dart pub get
```

## Run

```bash
dart run bin/receipt_api.dart
```

Server starts on `http://0.0.0.0:8080`.

## Endpoints

### `GET /health`
Health check.

```bash
curl http://localhost:8080/health
```

### `POST /scan`
Upload a receipt image and get parsed data back.

```bash
curl -X POST http://localhost:8080/scan \
  --data-binary @receipt.jpg \
  -H "Content-Type: image/jpeg"
```

**Response:**
```json
{
  "vendor": "Store Name",
  "date": "2024-01-15T00:00:00.000",
  "currencyCode": "PHP",
  "subtotal": 16.99,
  "tax": 1.36,
  "discount": null,
  "tip": null,
  "serviceCharge": null,
  "total": 18.35,
  "items": [
    {"name": "Coffee", "price": 3.50, "quantity": 1, "unitPrice": null},
    {"name": "2 x Sandwich", "price": 17.98, "quantity": 2, "unitPrice": 8.99}
  ],
  "parseError": null,
  "rawText": "..."
}
```
