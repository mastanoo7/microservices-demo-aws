# Service Dependencies

| Service | Depends on | Data dependency | Notes |
|---|---|---|---|
| frontend | productcatalogservice, currencyservice, cartservice, recommendationservice, adservice, checkoutservice | None | Public HTTP service |
| checkoutservice | cartservice, productcatalogservice, currencyservice, paymentservice, shippingservice, emailservice | Cart data | Coordinates order workflow |
| cartservice | redis-cart | Redis | Stores cart items |
| productcatalogservice | None | Static product catalog | Candidate for S3-backed catalog in future |
| currencyservice | None | Static exchange data | Mock conversion service |
| paymentservice | None | None | Mock external payment integration |
| shippingservice | None | None | Mock shipping logic |
| emailservice | None | None | Mock email delivery |
| recommendationservice | productcatalogservice | Product catalog | Generates recommendations |
| adservice | None | Static ad catalog | Contextual ad mock |
| redis-cart | None | Redis memory/disk | Stateful cache for cart |

## External Integrations

The demo application has no mandatory third-party production integrations. The generated AWS platform prepares integration points for payment providers, SMTP or SES, and product catalog storage, but keeps the application behavior compatible with upstream.
