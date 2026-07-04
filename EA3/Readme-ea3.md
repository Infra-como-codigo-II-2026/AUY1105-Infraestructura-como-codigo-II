# Evaluación Parcial N°3 — Gestión Avanzada de Recursos de Terraform
**AUY1105 - Infraestructura como Código II | DuocUC**

---

## Repositorio y Entorno de Trabajo

### Repositorio principal
```
AUY1105-Infraestructura-como-codigo-II
└── EA2/
    └── Evaluacion/         ← carpeta de trabajo para la EP3
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        ├── provider.tf
        └── terraform.tfstate
```

### Módulos utilizados (versionados en GitHub)
| Módulo | Repositorio | Versión |
|---|---|---|
| networking | `github.com/Infra-como-codigo-II-2026/terraform-aws-vpc-auy1105-grupo-6` | v1.0.0 |
| compute | `github.com/Infra-como-codigo-II-2026/terraform-aws-ec2-auy1105-grupo-6` | v1.0.0 |
| storage | `github.com/Infra-como-codigo-II-2026/terraform-aws-s3-auy1105-grupo-6` | v1.0.0 |

### Entorno de ejecución
- **Máquina de control (bastión):** EC2 Linux `ec2-34-207-21-70.compute-1.amazonaws.com`
- **Acceso:** Visual Studio Code con extensión Remote-SSH
- **Terminal activa:** `bash - Evaluacion` conectada al bastión
- **Infraestructura administrada:** EC2, VPC, subnets, SG y S3 desplegados como recursos separados del bastión

> ⚠️ Los comandos de Terraform se ejecutan **en el bastión**, no en la máquina local Windows. Confirmar siempre que la barra inferior de VS Code muestre `SSH: ec2-34-207-21-70...` antes de ejecutar.

---

## Infraestructura Desplegada (22 recursos)

```
module.compute.aws_instance.main
module.compute.aws_security_group.ssh_access
module.networking.aws_eip.nat_eip
module.networking.aws_internet_gateway.igw
module.networking.aws_nat_gateway.nat_gw
module.networking.aws_route.private_route
module.networking.aws_route.public_route
module.networking.aws_route_table.private_rt
module.networking.aws_route_table.public_rt
module.networking.aws_route_table_association.private_assoc_1
module.networking.aws_route_table_association.private_assoc_2
module.networking.aws_route_table_association.public_assoc_1
module.networking.aws_route_table_association.public_assoc_2
module.networking.aws_subnet.subnet_privada_1
module.networking.aws_subnet.subnet_privada_2
module.networking.aws_subnet.subnet_publica_1
module.networking.aws_subnet.subnet_publica_2
module.networking.aws_vpc.main
module.storage.aws_s3_bucket.main
module.storage.aws_s3_bucket_public_access_block.main
module.storage.aws_s3_bucket_server_side_encryption_configuration.main
module.storage.aws_s3_bucket_versioning.main
```

---

## Pipeline de despliegue inicial

La infraestructura base fue desplegada manualmente desde el bastión usando el flujo estándar de Terraform:

```bash
# 1. Inicializar Terraform y descargar módulos desde GitHub
terraform init

# 2. Verificar el plan antes de aplicar
terraform plan

# 3. Desplegar la infraestructura
terraform apply -auto-approve
```

> El `terraform init` descarga los módulos remotos desde GitHub usando la referencia `?ref=v1.0.0`, garantizando reproducibilidad con versiones fijas.

---

## ESCENARIO 1 — Recuperación del Estado de Terraform

### Objetivo
Simular la pérdida del archivo `terraform.tfstate` y recuperar el estado completo de los 22 recursos mediante `terraform state import`, sin destruir ni recrear ningún recurso en AWS.

### Resumen del procedimiento

| Paso | Acción | Comando clave | Archivo de evidencia |
|---|---|---|---|
| 0 | Mapear state original antes de borrar | `terraform state list` | `00_state_list_original.txt` |
| 1 | Simular pérdida y diagnosticar | `rm terraform.tfstate` + `terraform plan` | `01_plan_sin_state.txt` |
| 2 | Obtener IDs de los 22 recursos | `aws ec2 describe-*` + `aws s3api list-buckets` | `02_ids_recursos.txt`, `02_route_tables.txt` |
| 3 | Importar cada recurso al state | `terraform import module.*.resource id` | `03_verificacion_22_recursos.txt` |
| 4 | Verificar atributos importados | `terraform state show` | `04_show_vpc.txt`, `04_show_ec2.txt`, etc. |
| 5 | Validar sincronización completa | `terraform plan` | `05_plan_final.txt` |

### Detalle de ejecución

#### Paso 0 — Estado inicial documentado
```bash
terraform state list | tee 00_state_list_original.txt
```
Se guardó la lista de los 22 recursos como referencia para comparar la reconstrucción posterior.

📸 **Captura:** `escenario1_paso0_state_list_original.png`
> *Muestra la salida del `terraform state list` con los 22 recursos antes de eliminar el state*
<img width="608" height="182" alt="image" src="https://github.com/user-attachments/assets/bc30b083-d818-4980-99ba-3dff5ff13d13" />

---

#### Paso 1 — Simulación de la pérdida del state
```bash
cp terraform.tfstate ~/respaldo_manual_no_tocar.tfstate
rm terraform.tfstate
terraform plan | tee 01_plan_sin_state.txt
```
Sin el archivo de estado, Terraform propuso crear todos los recursos desde cero, evidenciando el problema:
```
Plan: 22 to add, 0 to change, 0 to destroy.
```

📸 **Captura:** `escenario1_paso1_plan_sin_state.png`
> *Muestra el resultado del `terraform plan` sin state, con `Plan: 22 to add` confirmando que Terraform perdió el registro de los recursos existentes*
<img width="786" height="36" alt="image" src="https://github.com/user-attachments/assets/9bb2bcc1-f822-41be-8f63-95d3010fdb32" />

---

#### Paso 2 — Obtención de IDs reales desde AWS
```bash
# Script consolidado que levanta todos los IDs en un solo archivo
echo "===== MÓDULO NETWORKING =====" | tee 02_ids_recursos.txt
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=mi-vpc" \
  --query "Vpcs[].VpcId" --output text | tee -a 02_ids_recursos.txt
# ... (subnets, IGW, EIP, NAT, SG, EC2, S3)

# Route tables en formato JSON para análisis detallado
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=vpc-02c1783c1b94081af" \
  --output json > 02_route_tables.txt
```

IDs identificados:
| Recurso | ID |
|---|---|
| VPC | `vpc-02c1783c1b94081af` |
| Subnet pública 1 (10.0.1.0/24) | `subnet-0cf73b1588b257039` |
| Subnet pública 2 (10.0.2.0/24) | `subnet-01a6ee652f1a91db0` |
| Subnet privada 1 (10.0.3.0/24) | `subnet-01e0f6cfab6d86b09` |
| Subnet privada 2 (10.0.4.0/24) | `subnet-009772a059b228292` |
| Internet Gateway | `igw-0fb5e19f92dea52ca` |
| Elastic IP (NAT) | `eipalloc-039af0f3b0a8ada51` |
| NAT Gateway | `nat-0273101a86d403f4f` |
| Route Table pública | `rtb-0916f52c1af4a6133` |
| Route Table privada | `rtb-03964f8ddd85282a9` |
| Security Group | `sg-0d82956068142cb22` |
| Instancia EC2 | `i-032f1b5b425e4581b` |
| S3 Bucket | `auy1105-dev-grupo-6-data` |

📸 **Captura:** `escenario1_paso2_ids_recursos_aws.png`
> *Muestra la salida del script de AWS CLI con todos los IDs organizados por módulo en el archivo `02_ids_recursos.txt`*
<img width="1412" height="854" alt="image" src="https://github.com/user-attachments/assets/d224aa39-1731-4598-9c07-358f79d038e0" />

---

#### Paso 3 — Importación de los 22 recursos
```bash
# MÓDULO NETWORKING
terraform import module.networking.aws_vpc.main vpc-02c1783c1b94081af
terraform import module.networking.aws_internet_gateway.igw igw-0fb5e19f92dea52ca
terraform import module.networking.aws_eip.nat_eip eipalloc-039af0f3b0a8ada51
terraform import module.networking.aws_subnet.subnet_publica_1 subnet-0cf73b1588b257039
terraform import module.networking.aws_subnet.subnet_publica_2 subnet-01a6ee652f1a91db0
terraform import module.networking.aws_subnet.subnet_privada_1 subnet-01e0f6cfab6d86b09
terraform import module.networking.aws_subnet.subnet_privada_2 subnet-009772a059b228292
terraform import module.networking.aws_nat_gateway.nat_gw nat-0273101a86d403f4f
terraform import module.networking.aws_route_table.public_rt rtb-0916f52c1af4a6133
terraform import module.networking.aws_route_table.private_rt rtb-03964f8ddd85282a9
terraform import module.networking.aws_route.public_route rtb-0916f52c1af4a6133_0.0.0.0/0
terraform import module.networking.aws_route.private_route rtb-03964f8ddd85282a9_0.0.0.0/0
terraform import module.networking.aws_route_table_association.public_assoc_1 \
  subnet-0cf73b1588b257039/rtb-0916f52c1af4a6133
terraform import module.networking.aws_route_table_association.public_assoc_2 \
  subnet-01a6ee652f1a91db0/rtb-0916f52c1af4a6133
terraform import module.networking.aws_route_table_association.private_assoc_1 \
  subnet-01e0f6cfab6d86b09/rtb-03964f8ddd85282a9
terraform import module.networking.aws_route_table_association.private_assoc_2 \
  subnet-009772a059b228292/rtb-03964f8ddd85282a9

# MÓDULO COMPUTE
terraform import module.compute.aws_security_group.ssh_access sg-0d82956068142cb22
terraform import module.compute.aws_instance.main i-032f1b5b425e4581b

# MÓDULO STORAGE
terraform import module.storage.aws_s3_bucket.main auy1105-dev-grupo-6-data
terraform import module.storage.aws_s3_bucket_public_access_block.main auy1105-dev-grupo-6-data
terraform import module.storage.aws_s3_bucket_versioning.main auy1105-dev-grupo-6-data
terraform import module.storage.aws_s3_bucket_server_side_encryption_configuration.main \
  auy1105-dev-grupo-6-data
```

> **Nota técnica:** Las Route Table Associations requieren formato compuesto `subnet-id/rtb-id`, no el `rtbassoc-id` simple. Esto fue identificado y corregido durante la ejecución.

```bash
# Verificación final: debe dar 22
terraform state list | wc -l
terraform state list | tee 03_verificacion_22_recursos.txt
```

📸 **Captura:** `escenario1_paso3_imports_exitosos.png`
> *Muestra la salida `Import successful!` de los imports ejecutados y el resultado de `wc -l` confirmando 22 recursos*
<img width="795" height="217" alt="image" src="https://github.com/user-attachments/assets/3a9c6089-f040-45f4-b346-54d4e714b2a9" />
<img width="793" height="199" alt="image" src="https://github.com/user-attachments/assets/58631a83-b666-44d5-b90c-4556d9a98ef8" />

📸 **Captura:** `escenario1_paso3_state_list_22_recursos.png`
> *Muestra la lista completa de los 22 recursos en el state reconstruido*
<img width="1414" height="534" alt="image" src="https://github.com/user-attachments/assets/7d9646de-84c4-4443-a1e0-69335ccf501c" />

---

#### Paso 4 — Verificación de atributos
```bash
terraform state show module.networking.aws_vpc.main | tee 04_show_vpc.txt
terraform state show module.networking.aws_internet_gateway.igw | tee 04_show_igw.txt
terraform state show module.networking.aws_nat_gateway.nat_gw | tee 04_show_nat.txt
terraform state show module.compute.aws_instance.main | tee 04_show_ec2.txt
terraform state show module.storage.aws_s3_bucket.main | tee 04_show_s3.txt
```

Atributos verificados:
- ✅ VPC: `cidr_block = "10.0.0.0/16"`, tags correctos
- ✅ IGW: `vpc_id = "vpc-02c1783c1b94081af"`
- ✅ NAT: `public_ip = "100.59.252.93"`, EIP correcta
- ✅ EC2: `instance_type = "t2.micro"`, `instance_state = "running"`
- ✅ S3: `versioning.enabled = true`, encriptación `AES256`

📸 **Captura:** `escenario1_paso4_state_show_vpc.png`
> *Muestra la salida de `terraform state show module.networking.aws_vpc.main` con cidr_block=10.0.0.0/16 y tags correctos*
<img width="770" height="527" alt="image" src="https://github.com/user-attachments/assets/1ec9e9f3-9f9b-4d00-bbb4-db460e226f03" />

---

#### Paso 5 — Validación final
```bash
terraform plan | tee 05_plan_final.txt
```

Resultado:
```
No changes. Your infrastructure matches the configuration.
```

📸 **Captura:** `escenario1_paso5_plan_final_no_changes.png`
> *Muestra el mensaje `No changes. Your infrastructure matches the configuration.` confirmando que la recuperación del state fue 100% exitosa*
<img width="796" height="443" alt="image" src="https://github.com/user-attachments/assets/fedf589d-c514-400e-8258-2799885f7de0" />

---

## ESCENARIO 2 — Actualización y Reforzamiento de Recursos

### Objetivo
Detectar y gestionar la desincronización entre recursos AWS y el state de Terraform usando `terraform refresh`, y forzar la recreación controlada de un recurso con `terraform taint`.

### Resumen del procedimiento

| Paso | Acción | Comando clave | Archivo de evidencia |
|---|---|---|---|
| 1 | Verificar baseline limpio | `terraform plan` | `06_plan_antes_drift.txt` |
| 1 | Crear drift manualmente en AWS | Consola AWS → SG → añadir regla 8080 | — |
| 1 | Detectar inconsistencia | `terraform plan` | `06_plan_con_drift.txt` |
| 2 | Sincronizar con refresh | `terraform refresh` | `07_terraform_refresh.txt` |
| 2 | Verificar post-refresh | `terraform plan` | `08_plan_post_refresh.txt` |
| 3 | Marcar EC2 para recreación | `terraform taint` | `09_taint_ec2.txt` |
| 3 | Observar impacto del taint | `terraform plan` | `10_plan_post_taint.txt` |
| 3 | Aplicar recreación | `terraform apply` | `11_apply_taint.txt` |
| 3 | Verificar nueva EC2 | `terraform state show` | `12_show_ec2_nueva.txt` |
| 4 | Remover marca taint | `terraform untaint` | `13_untaint_ec2.txt` |
| 4 | Validación final | `terraform plan` | `14_plan_final_escenario2.txt` |

### Detalle de ejecución

#### Paso 1 — Crear y detectar el drift

Se verificó primero que la infraestructura estaba completamente sincronizada:
```bash
terraform plan | tee 06_plan_antes_drift.txt
# Resultado: No changes.
```

Se introdujo manualmente una regla en el Security Group `ssh-access` desde la consola de AWS:
- **Puerto:** 8080 | **Protocolo:** TCP | **Origen:** 0.0.0.0/0 | **Descripción:** regla-manual-drift
<img width="800" height="260" alt="image" src="https://github.com/user-attachments/assets/9c747810-9449-40c6-a2f6-248ab7c8d89c" />

```bash
terraform plan | tee 06_plan_con_drift.txt
```

Resultado: Terraform detectó la inconsistencia:
```
~ module.compute.aws_security_group.ssh_access will be updated in-place
  ~ ingress = [
    - { from_port = 8080, description = "regla-manual-drift" }
  ]
Plan: 0 to add, 1 to change, 0 to destroy.
<img width="797" height="479" alt="image" src="https://github.com/user-attachments/assets/6760916c-23c8-4614-8d2e-afd1801c053e" />

```

📸 **Captura:** `escenario2_paso1_baseline_no_changes.png`
> *Muestra el resultado `No changes` del plan ejecutado antes de introducir el drift, confirmando el punto de partida limpio*
<img width="797" height="460" alt="image" src="https://github.com/user-attachments/assets/3913d81a-558c-43fc-b389-c9f24d455e78" />

📸 **Captura:** `escenario2_paso1_drift_detectado_plan.png`
> *Muestra el plan con el drift detectado: la regla del puerto 8080 aparece con signo `-` indicando que Terraform quiere eliminarla por no estar declarada en el código*
<img width="806" height="478" alt="image" src="https://github.com/user-attachments/assets/2c448e3b-85e0-446f-b23f-8b3c1373b8d6" />

---

#### Paso 2 — Sincronización con terraform refresh

```bash
terraform refresh | tee 07_terraform_refresh.txt
terraform plan | tee 08_plan_post_refresh.txt
```

El `terraform refresh` actualizó el state con los valores reales de AWS. El plan post-refresh confirmó que el state quedó sincronizado con la infraestructura real.

**Comparación antes/después del refresh:**
- `06_plan_antes_drift.txt` → `No changes` (infraestructura limpia antes del cambio manual)
- `08_plan_post_refresh.txt` → `1 to change` (state actualizado, Terraform detecta que el código no tiene la regla 8080)

> **Nota técnica:** En Terraform 1.x, `terraform plan` realiza un refresh implícito en cada ejecución. El valor del `terraform refresh` explícito radica en actualizar el state de forma aislada sin calcular un plan completo, útil en pipelines CI/CD donde se separa la sincronización de la planificación.

📸 **Captura:** `escenario2_paso2_terraform_refresh.png`
> *Muestra la ejecución de `terraform refresh` leyendo el estado real de los 22 recursos desde AWS*

---

#### Paso 3 — Reforzamiento con terraform taint

```bash
terraform taint module.compute.aws_instance.main | tee 09_taint_ec2.txt
terraform plan | tee 10_plan_post_taint.txt
<img width="794" height="478" alt="image" src="https://github.com/user-attachments/assets/cd217853-3cc8-425c-8712-0b0159f3f44e" />

```

El plan mostró que la EC2 sería destruida y recreada:
```
# module.compute.aws_instance.main is tainted, so must be replaced
-/+ resource "aws_instance" "main"
Plan: 1 to add, 0 to change, 1 to destroy.
```

```bash
terraform apply -auto-approve | tee 11_apply_taint.txt
terraform state show module.compute.aws_instance.main | tee 12_show_ec2_nueva.txt
```

La nueva instancia quedó correctamente desplegada con `instance_state = "running"`.

📸 **Captura:** `escenario2_paso3_taint_aplicado.png`
> *Muestra la confirmación del comando `terraform taint` y el plan posterior con `Plan: 1 to add, 1 to destroy` indicando la recreación programada*

📸 **Captura:** `escenario2_paso3_apply_ec2_recreada.png`
> *Muestra el resultado del `terraform apply` con la EC2 destruida y recreada exitosamente*

---

#### Paso 4 — Validación final y limpieza

```bash
terraform untaint module.compute.aws_instance.main | tee 13_untaint_ec2.txt
terraform plan | tee 14_plan_final_escenario2.txt
```

Resultado:
```
No changes. Your infrastructure matches the configuration.
```

📸 **Captura:** `escenario2_paso4_untaint_plan_final.png`
> *Muestra la ejecución de `terraform untaint` y el plan final con `No changes`, cerrando el Escenario 2 exitosamente*

---
## ESCENARIO 3 — Eliminación de Recursos del Estado de Terraform
 
### Objetivo
Eliminar el Security Group del estado de Terraform sin destruirlo físicamente en AWS, demostrando que un recurso puede dejar de ser administrado por Terraform manteniendo su existencia en la nube. El proceso utiliza `terraform state rm` para desasociar el recurso del state y luego se modifica el código del módulo para que el plan quede completamente limpio.
 
### Resumen del procedimiento
 
| Paso | Acción | Comando clave | Archivo de evidencia |
|---|---|---|---|
| 1 | Listar recursos gestionados por Terraform | `terraform state list` | `15_state_list_antes_rm.txt` |
| 2 | Eliminar SG del state con state rm | `terraform state rm` | `16_state_rm_sg.txt` |
| 2 | Verificar que el SG ya no aparece en el state | `terraform state list` | `17_state_list_despues_rm.txt` |
| 3 | Confirmar que el SG sigue existiendo en AWS | `aws ec2 describe-security-groups` | `18_sg_existe_en_aws.txt` |
| 3 | Comentar el bloque del SG en el código del módulo | Editar `.terraform/modules/compute/main.tf` y `outputs.tf` | — |
| 4 | Validar que Terraform no intenta recrear el SG | `terraform plan` | `19_plan_final_escenario3.txt` |
 
### Detalle de ejecución
 
#### Paso 1 — Identificar recursos gestionados por Terraform
```bash
terraform state list | tee 15_state_list_antes_rm.txt
<img width="795" height="477" alt="image" src="https://github.com/user-attachments/assets/f29985fb-1265-4b22-80f8-bc8e5d9d7aa8" />

```
 
Se confirmó que `module.compute.aws_security_group.ssh_access` estaba entre los 22 recursos gestionados por Terraform. Este es el recurso que se desasociará del state.
<img width="797" height="478" alt="image" src="https://github.com/user-attachments/assets/01b70c62-03ec-424b-9e19-3c5c2f0c145a" />

 
📸 **Captura:** `escenario3_paso1_state_list_22_recursos.png`
> *Muestra la lista completa de 22 recursos gestionados por Terraform, incluyendo `module.compute.aws_security_group.ssh_access` que será desasociado*
 <img width="1377" height="539" alt="image" src="https://github.com/user-attachments/assets/410ee430-fda4-449c-9b23-47b9d032554f" />

---
 
#### Paso 2 — Eliminar el Security Group del state con terraform state rm
```bash
terraform state rm module.compute.aws_security_group.ssh_access | tee 16_state_rm_sg.txt

```
 
Resultado:
```
Removed module.compute.aws_security_group.ssh_access
Successfully removed 1 resource instance(s).
```
 
El comando `terraform state rm` elimina el recurso del archivo de estado **sin destruirlo en AWS**. A partir de este momento Terraform deja de gestionar ese Security Group.
 
```bash
terraform state list | tee 17_state_list_despues_rm.txt

```
 
La lista pasó de 22 a 21 recursos. El SG ya no aparece.
 
📸 **Captura:** `escenario3_paso2_state_rm_exitoso.png`
> *Muestra la salida `Successfully removed 1 resource instance(s)` confirmando que el Security Group fue eliminado del state de Terraform*
> <img width="1081" height="639" alt="image" src="https://github.com/user-attachments/assets/d060bde6-e2fc-4b9c-b378-550e7f081310" />

 
📸 **Captura:** `escenario3_paso2_state_list_21_recursos.png`
> *Muestra la lista con 21 recursos, confirmando que `module.compute.aws_security_group.ssh_access` ya no está gestionado por Terraform*
 <img width="1059" height="643" alt="image" src="https://github.com/user-attachments/assets/02e17d8a-bf05-4d86-90eb-522337e24bef" />

---
 
#### Paso 3 — Confirmar que el SG sigue existiendo en AWS y eliminar del código
 
Se verificó que el Security Group seguía existiendo físicamente en AWS aunque ya no estuviera en el state de Terraform:
 
```bash
aws ec2 describe-security-groups --group-ids sg-0d82956068142cb22 \
  --query "SecurityGroups[].{Id:GroupId,Nombre:GroupName,Estado:Description}" \
  --output table | tee 18_sg_existe_en_aws.txt
```
 
Resultado:
```
| sg-0d82956068142cb22 | ssh-access | Permitir acceso SSH a instancias EC2 |
```
<img width="793" height="472" alt="image" src="https://github.com/user-attachments/assets/a802a6c2-d9fd-4fa2-85c1-93da4be53a45" />
<img width="792" height="260" alt="image" src="https://github.com/user-attachments/assets/29445aed-6cba-422c-8ba4-836fc4dc4122" />






 
El Security Group **sigue existiendo en AWS**. Esto demuestra que `terraform state rm` no destruye el recurso, solo lo desvincula de la gestión de Terraform.
 
A continuación se editó el código del módulo para que el plan quedara limpio. Como el SG estaba definido dentro del módulo de GitHub (no en el `main.tf` principal), se editaron los archivos del módulo en la caché local:
 
**Archivo:** `.terraform/modules/compute/main.tf`
 
Se comentó el bloque completo del Security Group y se reemplazó la referencia dinámica al recurso por el ID hardcodeado del SG existente:

```hcl
# resource "aws_security_group" "ssh_access" {
#   name        = var.security_group_name
#   description = "Permitir acceso SSH a instancias EC2"
#   vpc_id      = var.vpc_id
#   ingress { ... }
#   egress { ... }
#   tags = { ... }
# }
 
resource "aws_instance" "main" {
  ami                    = var.ami
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  # Antes: vpc_security_group_ids = [aws_security_group.ssh_access.id]
  # Después: ID hardcodeado del SG gestionado manualmente
  vpc_security_group_ids = ["sg-0d82956068142cb22"]
  tags = { ... }
}
```
 
**Archivo:** `.terraform/modules/compute/outputs.tf`
 
Se comentó el output que referenciaba el SG:


```hcl
# output "security_group_id" {
#   description = "ID del security group - gestionado manualmente"
#   value       = aws_security_group.ssh_access.id
# }
```
 
📸 **Captura:** `escenario3_paso3_sg_existe_en_aws.png`
> *Muestra la respuesta de AWS CLI confirmando que el Security Group `sg-0d82956068142cb22` sigue existiendo en AWS con el nombre `ssh-access`, demostrando que `state rm` no destruye el recurso físicamente*
>  <img width="1440" height="852" alt="image" src="https://github.com/user-attachments/assets/bb9ff636-5ee9-424b-b455-9746a99139fc" />
 
📸 **Captura:** `escenario3_paso3_modulo_compute_editado.png`
> *Muestra el archivo `.terraform/modules/compute/main.tf` con el bloque del SG comentado y la línea `vpc_security_group_ids` usando el ID hardcodeado en lugar de la referencia al recurso*
 <img width="1152" height="408" alt="image" src="https://github.com/user-attachments/assets/d7a6126d-f5b8-4eeb-a3a4-9425719d7a6c" /> 
---
 
#### Paso 4 — Validar que Terraform no intenta recrear el SG
```bash
terraform plan | tee 19_plan_final_escenario3.txt
```
 
Resultado:
```
No changes. Your infrastructure matches the configuration.
```
 
Terraform no propone recrear el Security Group porque el código ya no lo declara y el state tampoco lo tiene registrado. El recurso sigue vivo y funcional en AWS, simplemente dejó de ser administrado por Terraform.
 
📸 **Captura:** `escenario3_paso4_plan_final_no_changes.png`
> *Muestra el mensaje `No changes. Your infrastructure matches the configuration.` confirmando que Terraform no intenta recrear el Security Group, cerrando el Escenario 3 exitosamente*
 <img width="805" height="476" alt="image" src="https://github.com/user-attachments/assets/da6faaa2-3bbe-4f22-9242-9a1ad2173c5f" />

---
 
## Resumen de Archivos de Evidencia
 
### Escenario 1 — Recuperación del Estado
| Archivo | Captura asociada | Qué demuestra |
|---|---|---|
| `00_state_list_original.txt` | `escenario1_paso0_state_list_original.png` | 22 recursos antes de borrar el state |
| `01_plan_sin_state.txt` | `escenario1_paso1_plan_sin_state.png` | Plan: 22 to add (diagnóstico del problema) |
| `02_ids_recursos.txt` | `escenario1_paso2_ids_recursos_aws.png` | IDs de todos los recursos desde AWS CLI |
| `02_route_tables.txt` | — | JSON con detalle de route tables |
| `03_verificacion_22_recursos.txt` | `escenario1_paso3_state_list_22_recursos.png` | 22 recursos importados exitosamente |
| `04_show_vpc.txt` | `escenario1_paso4_state_show_vpc.png` | Atributos VPC verificados |
| `04_show_igw.txt` | — | Atributos IGW verificados |
| `04_show_nat.txt` | — | Atributos NAT Gateway verificados |
| `04_show_ec2.txt` | `escenario1_paso4_state_show_ec2_s3.png` | EC2 t2.micro running |
| `04_show_s3.txt` | `escenario1_paso4_state_show_ec2_s3.png` | S3 versioning+encriptación activos |
| `05_plan_final.txt` | `escenario1_paso5_plan_final_no_changes.png` | No changes — recuperación exitosa |
 
### Escenario 2 — Refresh y Taint
| Archivo | Captura asociada | Qué demuestra |
|---|---|---|
| `06_plan_antes_drift.txt` | `escenario2_paso1_baseline_no_changes.png` | Baseline limpio antes del drift |
| `06_plan_con_drift.txt` | `escenario2_paso1_drift_detectado_plan.png` | Drift detectado (regla 8080) |
| `07_terraform_refresh.txt` | `escenario2_paso2_terraform_refresh.png` | Refresh sincronizando 22 recursos |
| `08_plan_post_refresh.txt` | `escenario2_paso2_plan_post_refresh.png` | Plan post-refresh con 1 to change |
| `09_taint_ec2.txt` | `escenario2_paso3_taint_aplicado.png` | Taint aplicado a la EC2 |
| `10_plan_post_taint.txt` | `escenario2_paso3_taint_aplicado.png` | Plan: 1 to add, 1 to destroy |
| `11_apply_taint.txt` | `escenario2_paso3_apply_ec2_recreada.png` | Apply exitoso — EC2 recreada |
| `12_show_ec2_nueva.txt` | `escenario2_paso3_apply_ec2_recreada.png` | Nueva EC2 running |
| `13_untaint_ec2.txt` | `escenario2_paso4_untaint_plan_final.png` | Marca de taint removida |
| `14_plan_final_escenario2.txt` | `escenario2_paso4_untaint_plan_final.png` | No changes — Escenario 2 completo |
 
### Escenario 3 — Eliminación del State con terraform state rm
| Archivo | Captura asociada | Qué demuestra |
|---|---|---|
| `15_state_list_antes_rm.txt` | `escenario3_paso1_state_list_22_recursos.png` | 22 recursos gestionados incluyendo el SG |
| `16_state_rm_sg.txt` | `escenario3_paso2_state_rm_exitoso.png` | `Successfully removed 1 resource instance(s).` |
| `17_state_list_despues_rm.txt` | `escenario3_paso2_state_list_21_recursos.png` | 21 recursos — SG desasociado del state |
| `18_sg_existe_en_aws.txt` | `escenario3_paso3_sg_existe_en_aws.png` | SG sigue en AWS — `state rm` no destruye |
| `19_plan_final_escenario3.txt` | `escenario3_paso4_plan_final_no_changes.png` | No changes — Terraform no intenta recrear el SG |
 
---
 
## Conclusiones
 
### IL4.1 — Manipulación de archivos de estado
Se recuperó exitosamente el state de los 22 recursos usando `terraform import` con direcciones de módulo anidado (`module.networking.*`, `module.compute.*`, `module.storage.*`). Las Route Table Associations requirieron formato compuesto `subnet-id/rtb-id`. La validación con `diff` entre el state original y reconstruido confirmó recuperación sin pérdida de datos.
 
### IL4.2 — Optimización de configuraciones
Se documentaron los cambios observados antes y después de cada operación: comparación de planes pre/post drift, justificación del uso de `terraform refresh` vs refresh implícito en Terraform 1.x, y gestión del código del módulo para que el estado quede consistente tras la desasociación del SG.
 
### IL4.3 — Comandos avanzados de Terraform CLI
Se utilizaron correctamente los comandos:
- `terraform state import` — para recuperar los 22 recursos al state (Escenario 1)
- `terraform state list` y `terraform state show` — para verificar y auditar el state (Escenarios 1 y 3)
- `terraform refresh` — para sincronizar el state con la infraestructura real de AWS (Escenario 2)
- `terraform taint` y `terraform untaint` — para forzar recreación de la EC2 y luego remover la marca (Escenario 2)
- `terraform state rm` — para desasociar el Security Group del state sin destruirlo en AWS (Escenario 3)


---

*AUY1105 - Infraestructura como Código II | DuocUC | EP3 2024*
