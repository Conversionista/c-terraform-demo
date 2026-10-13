terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

resource "local_file" "person_config" {
    filename = "${path.module}/out/hello.txt"
    content  = "hello again from terraform\n"
}