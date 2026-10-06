variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type    = string
  default = "priomed"
}

variable "db_password" {
  type      = string
  sensitive = true
}
