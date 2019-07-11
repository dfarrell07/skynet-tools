# Create EC2 IAM role for master instance.
resource "aws_iam_role" "bootstrap_instance_role" {
  name = "${var.infra_id}-bootstrap-role"
  path = "/"

  tags = merge(map(
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy" "bootstrap_policy" {
  name = "${var.infra_id}-bootstrap-policy"
  role = aws_iam_role.bootstrap_instance_role.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ec2:Describe*",
                "ec2:AttachVolume",
                "ec2:DetachVolume"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Action": [
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::*",
            "Effect": "Allow"
        }
    ]
}
EOF
}

resource "aws_iam_instance_profile" "bootstrap_instance_profile" {
  name = "${var.infra_id}_bootstrap-instance-profile"
  role = aws_iam_role.bootstrap_instance_role.id
}