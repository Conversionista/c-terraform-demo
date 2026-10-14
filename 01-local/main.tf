terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

resource "local_file" "hello_text" {
  filename = "${path.module}/out/hello.txt"
  content  = "hello from terraform\n"
}