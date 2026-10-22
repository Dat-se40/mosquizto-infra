variable "vpc-id" {}
variable "web-sg-name" {}
variable "allowed-ssh-cidrs" {
  type = list(string)
}
variable "allowed-jenkins-cidrs" {
  type = list(string)
}