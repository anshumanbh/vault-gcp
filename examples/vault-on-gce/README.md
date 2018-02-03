# Vault on GCE Example

**Figure 1.** *diagram of Google Cloud resources*

![architecture diagram](./diagram.png)

## Set up the environment

Create a VPC network “vault” and a subnet “vault-subnet” (From GCLOUD Console). Configure the following:
```
Region - us-central1
IP range - 10.128.0.0/20
Regional (can be global also)
```

Enable the following GCLOUD APIs (From GCLOUD Console)
```
Google Compute Engine API
Google Cloud Storage
Google Cloud Key Management Service (KMS) API
Google Identity and Access Management (IAM) API
```

Create a KMS keyring and a KMS key (All commands should be executed from GCLOUD Cloud Shell from down here, unless stated otherwise)
```
gcloud kms keyrings create vault --location global
gcloud kms keys create vault-init --location global --keyring vault --purpose encryption
```

Setting up google project
```
gcloud config set project <project_id>
export GOOGLE_PROJECT=$(gcloud config get-value project)
git clone https://github.com/anshumanbh/terraform-google-vault.git
cd terraform-google-vault/examples/vault-on-gce
```

Next, create “terraform.tfvars” file:
```
cat - > terraform.tfvars <<EOF
	network = "vault"
	subnetwork = "vault-subnet"
	project_id = "${GOOGLE_PROJECT}"
	region = "us-central1"
	zone = "us-central1-b"
	machine_type = "n1-standard-1"
	storage_bucket = "${GOOGLE_PROJECT}-vault"
	kms_key_name = "vault-init"
	kms_keyring_name = "vault"
	vault_version = "0.9.0"
	EOF
```

If the cloud shell does not have terraform installed already, install it by:
```
curl -sL https://goo.gl/yZS5XU | bash
source ${HOME}/.bashrc
```

Run Terraform
```
terraform init
terraform plan
terraform apply (You’d have to enter “yes” at some point)
```

Destroying Terraform (only if you want to destroy the entire infrastructure)
```
terraform destroy
rm -rf certs/
rm -rf .terraform/
rm terraform.tfstate*
```

## Terraform’ing will provision the following items:

* TLS certificates for securing the Vault API
* Service Account for Vault Compute Engine instance
* IAM policy bindings that specify how Vault can interact with GCS, Cloud IAM, Cloud KMS
* Vault instance template and startup script that are used to install Vault
* Managed instance group for the instance template
* GCS bucket as the Vault storage backend
* GCS bucket for Vault assets like storing encrypted unseal keys, TLS certs & keys, root authentication token
* Vault instance created
* Unseal keys and the root token are stored encrypted (w/ KMS key) in GCS
* gcp-credentials.json file is generated


### NOTE: Terraform.tfstate contains sensitive information


---------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------
After a few minutes, the Vault instance will be ready.

## SSH Into Vault Instnace

Use SSH to connect to the Vault instance:

```
gcloud compute ssh $(gcloud compute instances list --limit=1 --filter=name~vault- --uri) -- sudo bash
```

> Note: the remainder of the commands will be run from within this SSH session.

Export the Vault environment variables:

```shell
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_CACERT=/etc/vault/vault-server.ca.crt.pem
export VAULT_CLIENT_CERT=/etc/vault/vault-server.crt.pem
export VAULT_CLIENT_KEY=/etc/vault/vault-server.key.pem
```

## Initialize Vault

Obtain the unseal keys from Cloud Storage and decrypt them using Cloud KMS:

```shell
export GOOGLE_PROJECT=$(gcloud config get-value project)
gcloud kms decrypt \
  --location=global  \
  --keyring=vault \
  --key=vault-init \
  --plaintext-file=/dev/stdout \
  --ciphertext-file=<(gsutil cat gs://${GOOGLE_PROJECT}-vault-assets/vault_unseal_keys.txt.encrypted)
```

The output will look like the following:

```
Unseal Key 1: oO1UNH4TPVZRFuGWUa9D0eciJ2LMMgi2PYxm/bLL/lt0
Unseal Key 2: +4q3O9LT46p22uTcDTYZyIVvVt+mxhB8OQ87vZFc3pkp
Unseal Key 3: tFnuYrDD1Xgkec3wFXhk93wIjEfq3kCOD34i16MkE+pl
Unseal Key 4: DFQhkl344Z+jpwr9L/looYjNYPAh8/UKGF5fXAO2Vj0W
Unseal Key 5: XOQVAZCKt6njWcF6IAP19ER1WnRqhH5MllyvcywBLtaw
Initial Root Token: 8d9b6907-0386-c422-cad8-624ceba2d0ae
```

Unseal Vault

```
vault unseal
```

> Run the command above at least 3 times, providing a different unseal key when prompted to unseal Vault.

Verify Vault is unsealed:

```
vault status
```

Authenticate to Vault as root:

```
vault auth ROOT_TOKEN
```

## Configure GCP Auth Backend

Enable GCP auth backend:

```
vault auth-enable gcp
```

Configure GCP backend:

```
vault write auth/gcp/config credentials=@/etc/vault/gcp_credentials.json
```

## Create a Vault role and login with signed JWT

Create a Vault role named `dev-role`:

```
GOOGLE_PROJECT=$(gcloud config get-value project)
vault write auth/gcp/role/dev-role \
  type="iam" \
  project_id="${GOOGLE_PROJECT}" \
  policies="default" \
  service_accounts="vault-admin@${GOOGLE_PROJECT}.iam.gserviceaccount.com"
```

> To add another service account run this: `vault write auth/gcp/role/dev-role/service-accounts add="SA_NAME@PROJECT_ID.iam.gserviceaccount.com"`

Get a signed JWT for the `dev-role`:

```
GOOGLE_PROJECT=$(gcloud config get-value project)
SERVICE_ACCOUNT=vault-admin@${GOOGLE_PROJECT}.iam.gserviceaccount.com
cat - > login_request.json <<EOF
{
  "aud": "vault/dev-role",
  "sub": "${SERVICE_ACCOUNT}",
  "exp": $((EXP=$(date +%s)+600))
}
EOF
```

```
JWT_TOKEN=$(gcloud beta iam service-accounts sign-jwt login_request.json signed_jwt.json --iam-account=${SERVICE_ACCOUNT} && cat signed_jwt.json)
```

Login to Vault with the signed JWT:

```
vault write -field=token auth/gcp/login role=dev-role jwt=${JWT_TOKEN} > ~/.vault-token
```

Test access by writing and reading a value to the cubbyhole

```
vault write /cubbyhole/hello value=world
vault read /cubbyhole/hello
```

Expected output:

```
Key     Value
---     -----
value   world
```

## Cleaning up

```
terraform destroy
```

Clean up the locally generated artifacts:

```
rm -rf certs/
rm vault_sa_key.json*
```