package ami

import (
	"fmt"
	"os"

	"golang.org/x/crypto/ssh"

	"github.com/amdonov/ami-builder/instance"
	myssh "github.com/amdonov/ami-builder/ssh"
	"github.com/tmc/scp"
)

type cloudInit struct {
	user      string
	imageUser string
	repo      string
}

func NewCloudInitProvisioner(user, imageUser, repo string) instance.Provisioner {
	return &cloudInit{user, imageUser, repo}
}

func (c *cloudInit) Provision(ip string, key []byte) error {
	client, err := myssh.Connect(c.user, ip, key)
	if err != nil {
		return err
	}
	defer client.Close()
	err = client.RunCommand(func(session *ssh.Session) error {
		return scp.CopyPath("ami.sh", "~/ami.sh", session)
	})
	if err != nil {
		return err
	}
	return client.RunCommand(func(session *ssh.Session) error {
		session.Stdout = os.Stdout
		return session.Run(fmt.Sprintf("sudo /bin/bash ./ami.sh %s %s", c.imageUser, c.repo))
	})
}
