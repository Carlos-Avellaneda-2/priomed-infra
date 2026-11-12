# priomed-infra

Infraestructura de PrioMed (Figura 3 del artículo).

- `docker-compose.yml` — servicio de clasificación + PostgreSQL + Redis. Los puertos se publican
  solo en `127.0.0.1`. Local: `cp .env.example .env && docker compose up --build`
- `deploy/` — despliegue en una sola instancia EC2 (Amazon Linux 2023) detrás de Apache httpd:
  - `deploy-ec2.sh`: instala swap, Docker compose/buildx y httpd, genera `.env` con contraseña
    aleatoria, levanta los contenedores, publica el portal y la documentación, y configura el proxy.
    Es idempotente.
  - `priomed-httpd.conf`: VirtualHost propio seleccionado por nombre
    (`priomed.<IP>.nip.io` / `priomed.<IP>.sslip.io`), para convivir con otros sitios del servidor.
  - `web/index.html`: portal con el estado del servicio, un formulario de demo y la documentación.
- `terraform/` — **esqueleto sin validar** de la VPC, subredes pública/privadas, RDS, S3, SQS y
  Secrets Manager. Falta: ALB, Auto Scaling de EC2, ElastiCache, NAT y VPC Endpoints. En AWS Academy
  Learner Lab varios servicios/roles IAM están restringidos; ajústalo a lo permitido.

## Despliegue en EC2

```bash
# Desde el equipo local, con los tres repos como carpetas hermanas
tar --exclude=.git -czf priomed.tgz priomed-classification-service priomed-infra priomed-docs
scp -i Llave.pem priomed.tgz ec2-user@<IP>:/tmp/
ssh -i Llave.pem ec2-user@<IP> 'mkdir -p ~/priomed && tar -xzf /tmp/priomed.tgz -C ~/priomed \
  && bash ~/priomed/priomed-infra/deploy/deploy-ec2.sh'
```

Resultado: `http://priomed.<IP>.nip.io/` (portal) y `http://priomed.<IP>.nip.io/docs` (Swagger).
El security group solo necesita los puertos 22 y 80; 8000/5432/6379 quedan internos.
Si la IP pública de la instancia cambia (stop/start sin Elastic IP), vuelve a correr el script.
