output "instance_profile_name" {
  value = var.use-lab-role ? "LabInstanceProfile" : aws_iam_instance_profile.instance_profile[0].name
}