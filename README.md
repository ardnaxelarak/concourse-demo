# concourse-demo

## Prerequisites
* Vagrant

## Setting up the Demo
#### Pushing Concourse to your VM
##### Using a local VM
Go to a directory that does not contain a `Vagrantfile` and run
```
vagrant init concourse/lite
vagrant up
```

This will create a local virtual machine, which you can access at http://127.0.0.1:8080.
##### Using a remote VM
Create a virtual machine using whatever service you wish.
Install `vagrant-managed-servers`:
```
vagrant plugin install vagrant-managed-servers
```
Create a `Vagrantfile`:
```
vagrant init tknerr/managed-server-dummy
```
Edit the `Vagrantfile` to include the information to connect to your virtual server:
```
Vagrant.configure(2) do |config|
  # insert code in this block
  
 config.vm.provider :managed do |managed, override|
    managed.server = "server.ip.address"
    override.ssh.username = "root"
    # this is a private key to use to connect to your server
    override.ssh.private_key_path = "/your/private_key_path"
  end
  
  config.vm.provision "bosh" do |c|
    # this is the path to the concourse manifest mentioned below
    # as is it will look for the manifest in the same directory as this Vagrantfile
    c.manifest = File.read(File.expand_path("../concourse_manifest.yml", __FILE__))
  end
end
```
In the same directory as the `Vagrantfile`, add a `concourse_manifest.yml`. An example is shown below:
```
---
name: concourse

releases: # you may have to update these attributes as new releases become available
  - name: concourse
    url: https://github.com/concourse/concourse/releases/download/v0.65.1/concourse-0.65.1.tgz
    version: 0.65.1
  - name: garden-linux
    url: https://github.com/concourse/concourse/releases/download/v0.65.1/garden-linux-0.307.0.tgz
    version: 0.307.0

networks:
  - name: concourse
    type: dynamic

jobs:
  - name: concourse
    instances: 1
    networks: [{name: concourse}]
    templates:
      - {release: concourse, name: atc}
      - {release: concourse, name: tsa}
      - {release: concourse, name: groundcrew}
      - {release: concourse, name: postgresql}
      - {release: garden-linux, name: garden}
    properties:
      atc:
        publicly_viewable: true # anyone can view the main pipeline page

        postgresql:
          address: 127.0.0.1:5432
          role: &atc-role
            name: atc
            password: dummy-password

        basic_auth_username: SOME_USERNAME # set to lock builds
        basic_auth_password: SOME_PASSWORD

      postgresql:
        databases: [{name: atc}]
        roles:
          - *atc-role

      tsa:
        atc:
          address: 127.0.0.1:8080
          username: SOME_USERNAME # use same credentials as above
          password: SOME_PASSWORD

      groundcrew:
        tsa:
          host: 127.0.0.1

        garden:
          address: 127.0.0.1:7777

      garden:
        disk_quota_enabled: false # disk quotas are not enabled by default on SoftLayer VMs

        listen_network: tcp
        listen_address: 0.0.0.0:7777

        allow_host_access: true

compilation:
  network: concourse

update:
  canaries: 0
  canary_watch_time: 1000-60000
  update_watch_time: 1000-60000
  max_in_flight: 10
```
With both of these files now in place, you can run
```
vagrant up
vagrant provision
```
to get the virtual machine loaded with concourse.
#### Creating your pipeline
If you do not already have the Fly CLI, go to your virtual machine in a web browser (connecting to port 8080), and download it.

To connect to your target, run `fly login`.
```
fly -t <target-name> login  -c https://server.ip:8080
```
This will prmopt you for a username and password, which were specified in the concourse manifest.
This will save the information for connecting to the target to `.flyrc` in your home directory,
and will allow you to connect to the machine in the future with `fly -t <taget-name> <whatever-command>`

For purposes of setting up this demo, I will assume the target has been saved as `demo`.

To add a pipeline to your target, use the `set-pipeline` command:
```
fly -t demo set-pipeline <arguments>
```
For this pipeline, from the `ci` directory, you can run
```
fly -t demo set-pipeline -c demo1.yml -v credentials.yml -p demo_1
```
In the above example, `demo1.yml` is the configuration for the pipeline, `credentials.yml` contains values to substitute into
the pipeline manifest, and `demo_1` is the name of the pipeline.
This will upload the pipeline to your VM, but it will initially be paused. It can be started by clicking the play button on
the UI, or by calling `fly unpause-pipeline`.

At this point your (very simple) pipeline is up and set to go! The jobs should start automatically, but you can also run them
manually by clicking the + icon on the page for the job.

## Explaining the demos
#### Demo 1
This is just a very simple pipeline meant to demonstrate the basics of using Concourse.
Begin by opening `demo1.yml` in your favorite text editor: this is the file that describes the entirety of the pipeline.

There are three main concepts in using Concourse: *resources*, *jobs*, and *tasks*. For an explanation of these three,
see http://concourse.ci/concepts.html.

Looking at our pipeline, we see we have one `resource`: this very repository, from GitHub. If you want to play around with
this demo, you should fork the project and update this resource to use your branch. Note also that you can specify which
branch of the repository to use. It is also possible to supply a private key if needed for connecting to a private repository.

The first job, `hello-world`, is fairly simple: we take in the resource for this github repository, and run a task. The
`trigger: true` in the `get` means that this job will automatically run every time this resource changes.
The task for this job is located in this repository, in tasks/hello.yml, which we shall take a look at:
```
image: docker:///ubuntu

inputs:
  - name: concourse-demo

run:
  path: concourse-demo/ci/scripts/hello.sh
```
First we see an image--this is a Docker container to run the task in. For this example I am just using a basic Ubuntu image,
but for something more complicated you could create a Docker image that already has everything you need pre-installed.

In the `inputs:` section, we specify all of the resources we are using--they can optionally have a path specified, or default
to being placed as a folder with the name of the resource.

Finally, we have what to run--since our resource was placed at the top level of our container, we can access it with a relative
path to concourse-demo, and find the script to run for the task inside there. The script itself is nothing particularly
interesting, just a very basic example.

Looking at the next job, there are some more interesting pieces: in our get of the resource for this repository, we additionally
added `passed: [hello-world]`. This means that any time the resource changes, this job won't be run until the hello-world job
has finished. In this case, it doesn't really matter whether hello-world runs first or not, but it is easy to imagine a case
where there is a job for running some tests on code before releasing it, and we would easily see that we only want to release
the code after we have passed the tests.

The other thing we notice is the parameter being set: in this case, `NAME: {{user}}`. This sets the `NAME` environment variable
to whatever we set it to. Entries enclosed in double braces are replaced according to the `--vars-from` file we specified. This
is useful for supplying credentials like passwords or private keys without having to include them in public places--we can
configure the values in a separate file and pass them in.

#### More Demos
TBD
