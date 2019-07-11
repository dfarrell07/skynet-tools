# Create EC2 IAM role for master instance.
resource "aws_iam_role" "master_instance_role" {
  name = "${var.infra_id}-master-role"
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

resource "aws_iam_role_policy" "master_policy" {
  name = "${var.infra_id}-master-policy"
  role = aws_iam_role.master_instance_role.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "ec2:*",
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Action": "iam:PassRole",
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Action": [
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::*",
            "Effect": "Allow"
        },
        {
            "Action": "elasticloadbalancing:*",
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
EOF
}

resource "aws_iam_instance_profile" "master_instance_profile" {
  name = "${var.infra_id}_master-instance-profile"
  role = aws_iam_role.master_instance_role.id
}
