locals {
  short_cluster_name = element(split("-", var.infra_id), 1)
  file_path          = ".config/${local.short_cluster_name}/bootstrap.ign"
}

# Create bootstrap bucket
resource "aws_s3_bucket" "bootstrap_bucket" {
  bucket        = "${var.infra_id}-bootstrap"
  acl           = "private"
  region        = var.aws_region
  force_destroy = true

  tags = merge(map(
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Upload bootstrap.ign to s3 bucket
resource "aws_s3_bucket_object" "bootstrap_config" {
  bucket = aws_s3_bucket.bootstrap_bucket.id
  key    = "bootstrap.ign"
  source = local.file_path

  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  etag = filemd5(local.file_path)
}


