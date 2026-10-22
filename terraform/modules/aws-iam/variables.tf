variable "iam-role" {}
variable "iam-policy" {}
variable "instance-profile-name" {}
variable "use-lab-role" {
  type    = bool
  default = true
}