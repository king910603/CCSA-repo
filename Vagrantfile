# -*- mode: ruby -*-
# Two-node K3s cluster for HW3.
#
#   vagrant up          create/boot both VMs, install K3s, deploy the app
#   vagrant halt        shut down both VMs (data on the PVC is kept)
#   vagrant destroy -f  delete both VMs and all cluster data
require "fileutils"
require "securerandom"

K3S_VERSION = "v1.33.13+k3s1"
SERVER_IP   = "192.168.56.10"
AGENT_IP    = "192.168.56.11"
BOX         = "bento/ubuntu-24.04"

# Vagrant for Windows is an x64 program, so on Windows-on-ARM laptops its
# :auto detection picks the amd64 box. Ask Windows for the real CPU instead;
# HW3_BOX_ARCH (arm64/amd64) overrides the choice.
BOX_ARCH = ENV.fetch("HW3_BOX_ARCH") do
  ENV["PROCESSOR_IDENTIFIER"].to_s.start_with?("ARM") ? "arm64" : :auto
end

# State shared between the host and both VMs (join token, kubeconfig, image
# tarball). It lives in the synced folder, so the guests see it at
# /vagrant/.cluster.
CLUSTER_DIR = File.join(__dir__, ".cluster")
TOKEN_FILE  = File.join(CLUSTER_DIR, "node-token")
FileUtils.mkdir_p(CLUSTER_DIR)
File.write(TOKEN_FILE, SecureRandom.hex(32)) unless File.exist?(TOKEN_FILE)
K3S_TOKEN = File.read(TOKEN_FILE).strip

Vagrant.configure("2") do |config|
  config.vm.box = BOX
  config.vm.box_architecture = BOX_ARCH
  config.vm.box_check_update = false

  config.vm.provider "virtualbox" do |vb|
    vb.cpus = 2
    vb.memory = 2048
    vb.linked_clone = true
  end

  # Control-plane node. Builds the application images once per source change.
  config.vm.define "k3s-server", primary: true do |server|
    server.vm.hostname = "k3s-server"
    server.vm.network "private_network", ip: SERVER_IP

    server.vm.provision "k3s", type: "shell", path: "scripts/server.sh",
      env: { "K3S_VERSION" => K3S_VERSION, "K3S_TOKEN" => K3S_TOKEN, "NODE_IP" => SERVER_IP }
    server.vm.provision "images", type: "shell", path: "scripts/build-images.sh", run: "always"
  end

  # Worker node. Comes up second, so it also runs the deployment step once
  # both nodes exist.
  config.vm.define "k3s-agent" do |agent|
    agent.vm.hostname = "k3s-agent"
    agent.vm.network "private_network", ip: AGENT_IP

    agent.vm.provision "k3s", type: "shell", path: "scripts/agent.sh",
      env: { "K3S_VERSION" => K3S_VERSION, "K3S_TOKEN" => K3S_TOKEN,
             "NODE_IP" => AGENT_IP, "SERVER_IP" => SERVER_IP }
    agent.vm.provision "images", type: "shell", path: "scripts/import-images.sh", run: "always"
    agent.vm.provision "deploy", type: "shell", path: "scripts/deploy.sh", run: "always",
      env: { "SERVER_IP" => SERVER_IP }
  end
end
