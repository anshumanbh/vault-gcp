/*
 * Copyright 2017 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

variable network {}
variable subnetwork {}
variable project_id {}
variable region {}
variable zone {}
variable machine_type {}
variable storage_bucket {}
variable kms_key_name {}
variable kms_keyring_name {}
variable vault_version {}

provider google {
  region = "${var.region}"
}

module "vault" {
  // source               = "github.com/GoogleCloudPlatform/terraform-google-vault"
  source               = "../../"
  network              = "${var.network}"
  subnetwork           = "${var.subnetwork}"
  project_id           = "${var.project_id}"
  region               = "${var.region}"
  zone                 = "${var.zone}"
  machine_type         = "${var.machine_type}"
  storage_bucket       = "${var.storage_bucket}"
  kms_key_name         = "${var.kms_key_name}"
  kms_keyring_name     = "${var.kms_keyring_name}"
  vault_version        = "${var.vault_version}"
  force_destroy_bucket = true
}
