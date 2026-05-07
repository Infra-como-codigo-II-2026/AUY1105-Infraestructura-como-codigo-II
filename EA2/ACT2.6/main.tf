module "vpc" {
  source                = "./vpc_module"
  vpc_cidr              = var.vpc_cidr
  vpc_name              = var.vpc_name
  subnet_publica_1_cidr = var.subnet_publica_1_cidr
  subnet_publica_2_cidr = var.subnet_publica_2_cidr
  subnet_privada_1_cidr = var.subnet_privada_1_cidr
  subnet_privada_2_cidr = var.subnet_privada_2_cidr
  az_1                  = "us-east-1a"
  az_2                  = "us-east-1b"
}

module "ec2" {
  source             = "./ec2_module"
  key_name           = var.key_name
  public_key         = "vockey.pem"
  ami                = "ami-0eb38b817b93460ac"
  subnet_id          = module.vpc.subnet_publica_1_id
  vpc_id             = module.vpc.vpc_id
  instance_name      = var.instance_name
  use_security_group = false
}


