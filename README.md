# priomed-infra

Infraestructura de PrioMed (Figura 3 del artículo).

- `docker-compose.yml` — entorno local: servicio de clasificación + PostgreSQL + Redis.
  `cp .env.example .env && docker compose up --build`
- `terraform/` — **esqueleto sin validar** de la VPC, subredes pública/privadas, RDS, S3, SQS y
  Secrets Manager. Falta: ALB, Auto Scaling de EC2, ElastiCache y VPC Endpoints. En AWS Academy
  Learner Lab varios servicios/roles IAM están restringidos; ajústalo a lo permitido.
