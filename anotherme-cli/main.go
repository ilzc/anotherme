package main

import "github.com/user/anotherme-cli/cmd"

var version = "dev"

func main() {
	cmd.SetVersion(version)
	cmd.Execute()
}
