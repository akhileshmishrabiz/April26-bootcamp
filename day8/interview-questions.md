# Interview Q&A: ECS, ECR, ALB, Containers in Production

## Batch 1: ECS Fundamentals, Networking, ALB (Q1-15)

---

### Q1: When would you choose ECS over EKS? Walk me through the decision.

ECS is the right choice for 99% of use cases. EKS is for that remaining 1%.

The decision comes down to three things. Complexity, scale, and ecosystem.

Most apps are simple. A two-tier app or a three-tier app. One web app, maybe a database, maybe a worker. For that kind of workload, ECS gives you everything you need. Self-healing, autoscaling, load balancer integration. You set it up once and forget it.

You go to EKS when you have real microservices. Not five services. We are talking twenty, fifty, a hundred services that all talk to each other. They scale independently. Different teams own different services. Each one might be written in a different language. That is when Kubernetes ecosystem matters. You need tools like Keda for custom scaling, Karpenter for node scaling, service mesh for traffic management, all of that.

People think it is about user count. It is not. A blog post with one million users is still a two-tier app. Run it on ECS. But Netflix with one million users has video streaming, recommendations, payment, account management, all as separate services. That needs EKS.

The hidden cost is people. Kubernetes engineers cost more. You need more of them. You need to patch the cluster, manage upgrades, handle the complexity. ECS hides all of that. AWS manages it for you.

Rule of thumb. Start with ECS. Move to EKS only when you genuinely outgrow it. Most companies never do.

---

### Q2: Explain the difference between an ECS task, service, and cluster. Why is the cluster a logical unit?

Three layers. Bottom up.

A task is the smallest unit in ECS. It wraps one or more containers. You define how to run the container in a task definition. What image, what port, how much CPU, how much memory, what environment variables. The task is the running instance of that definition.

A service sits on top of tasks. It manages multiple tasks for you. If you want two tasks running all the time, the service makes sure two are always running. One dies, service brings up a new one. That is your self-healing. Service also handles autoscaling and load balancer integration.

A cluster is the container for all of this. It holds your services and tasks. But here is the key thing. The cluster is logical, not physical. Unlike a Kubernetes cluster which is actual compute, an ECS cluster does not have any compute attached to it by default. It is just a namespace where your services live.

Why does that matter. Because creating a cluster costs nothing. It is just a logical grouping. The compute comes from Fargate or your EC2 instances. The cluster itself is free. That is why you can have multiple clusters for different environments without worrying about cost.

If you know Kubernetes, the mapping is simple. ECS task is like a pod. ECS service is like a deployment. ECS cluster is like a Kubernetes namespace, not the actual cluster.

---

### Q3: What is the difference between an ECS task role and a task execution role? Give an example of each.

Two different roles for two different jobs.

Task execution role runs before your container starts. It does the setup work. Pulling the image from ECR. Creating the log group in CloudWatch. Reading secrets from Secrets Manager. Without this role, your container never starts.

Task role runs after your container starts. It is what your application uses to call other AWS services from inside the container.

Example. You have a web app on ECS. The app pulls images from ECR and writes logs to CloudWatch. That is execution role work. The app does not call any AWS services itself. So task role can be empty.

Now different example. You have an automation that runs in ECS. It reads files from S3, processes them, writes to DynamoDB, sends emails through SES. The execution role still pulls the image and writes logs. But the task role needs S3 read, DynamoDB write, SES send permissions.

For most web apps you only need the execution role. The AmazonECSTaskExecutionRolePolicy gives you everything you need. ECR pull, CloudWatch logs, that is it.

You only think about task role when your app talks to other AWS services. That is the rule.

---

### Q4: What is the difference between Fargate, EC2 launch type, and managed instances in ECS? When would you pick each?

Three options. Different levels of control vs convenience.

Fargate is fully managed. You do not see any VMs. AWS handles the compute. You just tell ECS to run my container, it runs it somewhere. You pay a bit more per hour but you do not patch anything, you do not manage AMIs, you do not worry about node scaling. This is what 95% of people should use.

EC2 launch type means you bring your own EC2 instances. You create an autoscaling group, register it with ECS, and ECS runs your tasks on those instances. You control which instance type, which AMI, when to patch. You save some money on compute but you pay in operational overhead. You also have to manage node scaling separately from task scaling.

Managed instances is new. AWS launched it a few months back. Think of it as Fargate-like convenience but on EC2 underneath. AWS manages the patching, the AMIs, the scaling. But you can choose certain things like instance types. It is a middle ground.

When do you pick what.

Fargate for almost everything. Default choice. You came to AWS for convenience, use the convenience.

EC2 launch type when you have specific compliance needs. Some companies require workloads on specific instance types. Or you already have a large EC2 reservation and want to use it.

Managed instances when you want Fargate ease but need EC2 underneath for cost or specific reasons.

The general principle. You pay for convenience or you do the work yourself. Same principle as cloud vs on-prem. Just at a smaller scale.

---

### Q5: Why does a standalone ECS task not auto-restart when it stops, but a service does?

Different jobs. Different behavior.

A task is for one-shot work. Run a database migration. Process a batch of files. Generate a report. The task does its job and dies. You do not want it to restart. That would be wrong. The job is done.

A service is for long-running work. A web app. An API. Something that should never be down. The service watches the task. If the task dies, the service brings up a new one. That is the self-healing.

Behind the scenes the service has a desired count. If you say desired count is two, the service keeps two tasks running no matter what. Kill one manually, the service starts a new one immediately. Set desired count to zero if you want to stop the service without deleting it.

A task does not have a desired count. It just runs once. When it stops, it stays stopped.

So the question to ask yourself when designing. Is this a one-time job or a long-running app. One-time job, use task directly. Long-running app, wrap it in a service.

---

### Q6: Why do we put ECS tasks in private subnets behind an ALB instead of giving them public IPs?

Three reasons. Security, scaling, and HA.

Security first. Your tasks are running your application. They should not be reachable from the internet directly. Anything that talks to the internet is an attack surface. Put your tasks in private subnets and the only way in is through the ALB. The ALB becomes your single controlled entry point.

Scaling second. If you have public IPs on each task, every time a task dies and a new one comes up, the IP changes. Now you have to update DNS, update firewall rules, update everything else that depends on that IP. With an ALB in front, the ALB DNS name stays the same. Tasks come and go behind it without anyone noticing.

HA third. Tasks spread across multiple AZs. Each one in a different private subnet. If one AZ goes down, the ALB still routes traffic to the healthy ones. With public IPs, you would need to manage failover yourself.

There is also the practical thing. With multiple tasks running, you cannot use IP-based routing anymore. Which IP do you give your users. The ALB solves that. It has its own DNS name, you map your domain to it, and it figures out which task gets the traffic.

So the pattern is always the same. ALB in public subnets, tasks in private subnets, database in a separate isolated subnet. This is how production deployments look.

---

### Q7: Your ECS tasks are in private subnets and failing to pull from ECR. Walk me through what is wrong and the two ways to fix it.

Private subnets have no path to the internet by default. ECR endpoint is a public endpoint. So your task cannot reach it. That is why the image pull fails.

Two ways to fix this.

Option one is a NAT gateway. You create a NAT gateway in a public subnet. Then you update the route table attached to your private subnets. Add a route that says zero zero zero zero zero zero, send it to the NAT gateway. Now your private subnets can reach anything on the internet, including ECR.

Option two is VPC endpoints. You create VPC endpoints for ECR API, ECR DKR, S3, and CloudWatch Logs. These are private endpoints inside your VPC. Your tasks reach ECR through the AWS backbone without ever touching the internet.

Tradeoffs.

NAT gateway is simpler. One thing to configure. It solves not just ECR but everything else. Your tasks need to talk to any AWS service or any external API, NAT handles it all. But NAT is a single multipurpose tool that charges you per hour and per GB of data.

VPC endpoints are more compliant. Traffic never leaves the AWS network. Better for security and audit. But you need multiple endpoints for different services. Each one has an idle hourly charge plus data charges. If you have ten endpoints, you are paying for ten hourly charges.

The decision is contextual. For a simple setup with one or two apps, NAT gateway is cheaper and easier. For a large enterprise with strict compliance, VPC endpoints win.

There is also one detail people miss. The S3 gateway endpoint is free. Always create that one. It does not cost anything and it speeds up S3 access from private subnets.

---

### Q8: For a production ECS deployment, how many NAT gateways do you need and why? What if you only have one, does it still work across multiple AZs?

For real production, you need one NAT gateway per AZ. Two AZs, two NAT gateways. Three AZs, three NAT gateways.

The reason is HA. NAT gateway lives in a single AZ. If that AZ goes down, your NAT goes down. If your NAT goes down, every private subnet that depends on it loses internet access. New tasks cannot pull images. Existing tasks cannot reach external APIs.

With one NAT per AZ, each AZ has its own path to the internet. One AZ failure does not affect the others.

Now the second part of the question. What if you only have one NAT gateway and your tasks span multiple AZs. Does it still work.

Yes, it works. But there is a catch.

Here is why it works. NAT gateway is attached to a subnet, but the route to it is in the route table. If your route table is associated with multiple subnets across multiple AZs, all those subnets route through that single NAT. So tasks in AZ-A and tasks in AZ-B both reach the internet through the NAT in AZ-A.

The catch is cross-AZ data transfer. AWS charges for data going between AZs. Not within the VPC for same-AZ traffic, but cross-AZ does cost money. So your tasks in AZ-B are paying a small fee to use the NAT in AZ-A.

The bigger catch is HA. If AZ-A goes down, the NAT is gone. Both AZs lose internet. That defeats the purpose of running across multiple AZs.

For learning and demos, one NAT gateway is fine. For production, always one per AZ. Pay the extra cost. The HA is worth it.

---

### Q9: What is awsvpc network mode and why is it the default for Fargate? How is it different from bridge or host networking in plain Docker?

In plain Docker, you have networking options. Bridge is the default, host is when the container shares the host network, and there are a few others. These work within a single VM. The container gets an IP on the host's internal network.

awsvpc is different. It gives each ECS task its own ENI, its own elastic network interface, inside your VPC. The task gets a real VPC IP, not a Docker bridge IP. From the network point of view, the task looks like a normal EC2 instance.

Why does that matter.

Because in Fargate you do not have a single VM. AWS is running your tasks across compute that you do not see. There is no host network to bridge to. So awsvpc was built to make containers first-class VPC citizens.

With awsvpc your task can have its own security group. It can be in a specific subnet. It can be reached by ALB IP targets. None of that works if the container is hidden behind a host bridge.

The difference in your head. Docker bridge networking is local to one VM. awsvpc is global to your VPC. Same idea, different scope.

This is also why Fargate forces awsvpc. There is no other option that makes sense without an underlying host you control.

---

### Q10: Is there a cost for cross-AZ data transfer within the same VPC? What about cross-region?

Yes, cross-AZ within the same VPC has a charge. Small per-GB charge in both directions. People often miss this because it is not obvious until you see the bill.

Same AZ within the VPC is free. So if your ECS task and your RDS database are both in AZ-A, no data transfer cost. If they are in different AZs, you pay.

Cross-region is much more expensive. Same per-GB rate as data leaving AWS. So traffic between AZs is small money, traffic between regions is real money.

Data leaving AWS to the public internet is the most expensive. Inbound is free in most cases. Outbound to internet is where you pay the most.

This matters for architecture decisions. If you have a chatty app that hits the database thousands of times per second, putting them in different AZs adds up. Same-AZ placement for chatty workloads saves real money.

But you do not always optimize for cost. HA needs you to spread across AZs. So you accept the small cross-AZ cost as the price of high availability. Trade-off, not a fixed answer.

Quick rule. Within VPC same AZ is free. Within VPC different AZ has small cost. Cross-region or out to internet is expensive.

---

### Q11: You are putting a load balancer in front of an ECS service. ALB or NLB? Why? When would the answer flip?

For a web app, always ALB.

The reason is layer 7. ALB is layer 7, application layer. It understands HTTP and HTTPS. It can do path-based routing, host-based routing, SSL termination, sticky sessions. All of that is what a web app needs.

NLB is layer 4, network layer. It just forwards TCP and UDP. It does not understand HTTP. It cannot do path-based routing. It cannot terminate SSL on its own.

So for any normal web traffic, ALB.

When does the answer flip. A few cases.

First, extreme performance. NLB is faster because it does less work. If you have millions of requests per second and you do not need layer 7 features, NLB handles it better.

Second, non-HTTP traffic. Database connections, custom TCP protocols, gaming traffic. ALB cannot do this. NLB can.

Third, static IPs. NLB can give you static IPs. ALB cannot. If a client needs to whitelist your IPs in their firewall, NLB is the answer.

Fourth, Kubernetes ingress patterns. Sometimes the NLB sits in front and does the TCP forwarding, and an ingress controller inside the cluster handles HTTPS and path routing. The NLB does the network layer, something else does the application layer.

But for an ECS web app behind ALB on HTTPS, default answer is ALB. Always.

---

### Q12: Why must an ALB span at least two subnets in two different AZs? What happens at the DNS level?

Because AWS wants to enforce high availability. You cannot create an ALB in just one AZ. The console will not let you.

When you create an ALB and pick two subnets in two AZs, AWS creates an ALB node in each AZ behind the scenes. Each node has its own IP. You do not see these nodes, you see one ALB. But underneath there are two.

At the DNS level this is why an nslookup on the ALB DNS name gives you multiple IPs. Each IP belongs to one of those nodes. The DNS resolves to all of them. Clients pick one and connect.

If one AZ goes down, that node goes down with it. The DNS still has the other node's IP. Traffic flows through the surviving AZ. Your users do not notice anything.

This is also why the IPs of an ALB can change over time. AWS replaces unhealthy nodes, scales them up under load, all of that happens behind the DNS. You never code against the IP. You always use the DNS name.

If you give it three subnets in three AZs, you get three nodes, three IPs. Same idea, just more HA.

The takeaway. ALB looks like one thing but it is multiple nodes behind a DNS name. Two AZs minimum is the AWS-enforced HA floor.

---

### Q13: When registering Fargate tasks to a target group, why do you pick target type IP instead of Instance?

Instance target type means the targets are EC2 instance IDs. The target group looks up the IP of the EC2 instance and sends traffic there.

Fargate does not give you EC2 instances. There are no instance IDs. You do not see the underlying compute. So instance target type is useless for Fargate.

IP target type means the targets are raw IPs. With awsvpc network mode, each Fargate task has its own VPC IP. The target group registers those IPs directly. Task starts, ECS registers its IP with the target group. Task dies, ECS deregisters the IP.

This is also why awsvpc is required. Without it, the task does not have its own IP, and the target group has nothing to register.

If you accidentally pick instance target type for Fargate, the target group will be empty. No targets will register. Health checks will not run. The ALB will return 503.

Same applies to EC2 launch type with awsvpc. Even on EC2, if you are using awsvpc mode, IP target type is the right choice. Instance target type is for old-school bridge mode where containers share the host network.

So the rule is simple. Fargate equals IP target type. Always.

---

### Q14: Your ECS targets are showing unhealthy in the target group. Walk me through your debugging checklist.

Six things to check, in order.

First, is the task actually running. Go to the ECS service tasks tab. If the task is in PENDING or STOPPED, you have a task startup problem, not a health check problem. Look at the task logs. Usually it is image pull failure, log group missing, or secret access denied.

Second, what is the health check path. Your target group is hitting some path like slash or slash health. Does that path actually return a 200 from your app. Hit it manually with curl from within the VPC. If your app returns a 302 redirect because slash redirects to login, the health check fails because it expects 200. Change the path to something that returns 200 directly.

Third, is the port correct. Target group is checking port 8000 but your app listens on 5000. Check your task definition port mapping matches the target group port. Common mistake.

Fourth, is the security group right. The ALB security group must allow inbound traffic from the internet on 443. The ECS security group must allow inbound traffic on the app port, but only from the ALB security group, not from zero zero zero zero zero zero. If the ECS security group does not allow the ALB to reach the task, health checks time out.

Fifth, is the health check threshold too tight. By default it might be 2 successful checks every 10 seconds. If your app takes 30 seconds to start, the target gets killed before it ever becomes healthy. Increase the healthy threshold timing.

Sixth, look at the actual health check logs. ALB access logs to S3 if enabled. Or CloudWatch metrics on the target group. They tell you exactly what response the health check is getting.

Most of the time it is path or security group. Those two account for 80% of unhealthy target issues.

---

### Q15: What is the difference between HTTP status codes 200, 301, 302, 401, 403, 404, 500, 502, 503? Which ones matter for ALB health checks?

Three families to understand.

200 series means success. 200 means OK, request worked, response is here. This is what your ALB health check expects by default.

300 series means redirection. 301 is permanent redirect, 302 is temporary redirect. Your app is saying go look somewhere else for this. Browsers follow it automatically. But ALB health checks do not. If your app returns 302 on the health check path, the health check fails.

400 series means client error. The request was wrong somehow. 401 is unauthorized, you are not logged in. 403 is forbidden, you are logged in but not allowed. 404 is not found, the URL does not exist. These tell you the client did something wrong.

500 series means server error. The app crashed or is broken. 500 is generic internal error. 502 is bad gateway, often means ALB cannot reach the target. 503 is service unavailable, often means no healthy targets in the target group.

Which ones matter for ALB health checks.

The default success code is 200. You can configure the target group to accept other codes, like 200 to 299, or specific codes like 200 and 302. If your app returns 302 on the health check, you can either change the path to something that returns 200, or change the success code in the target group config to include 302.

In troubleshooting, 502 and 503 from the ALB usually mean the target group is the problem. 502 means the target rejected the connection or returned a malformed response. 503 means there are no healthy targets at all. Both point you back to checking the ECS tasks and target group health.

These are the codes you should know cold. Anyone doing DevOps work runs into them every day.

---
# Interview Q&A: ECS, ECR, ALB, Containers in Production

## Batch 2: ECR, Secrets, RDS, Deployments (Q16-28)

---

### Q16: Walk me through what happens when you run aws ecr get-login-password piped into docker login. What is each piece doing, and why do you need to be authenticated to AWS first?

Two different authentications happening. People get confused because they look like one thing.

First piece. aws ecr get-login-password. This is an AWS CLI command. It talks to ECR and asks for a temporary token. ECR generates a token and returns it. This token is short-lived, valid for twelve hours.

For this command to work, you must already be authenticated to AWS. The AWS CLI uses your credentials, your access key or your SSO session, to make the API call. Your IAM user or role needs ECR permissions to get this token. If you do not have those permissions, the command fails before it even tries.

Second piece. The token gets piped into docker login. Now docker login is a Docker command, nothing to do with AWS. It just expects a username and a password. The username is hardcoded to AWS. The password is that token we just got. Docker stores this auth in your local config file, usually in dot docker slash config dot json.

After this, any docker push or docker pull command to ECR uses that stored auth. Docker does not know it is AWS. It just sees a registry and credentials.

The two-layer thing is important to understand. AWS auth happens first because ECR is an AWS service. Docker auth happens second because Docker is the tool actually moving the image. You cannot skip the first. Without AWS permissions, you cannot get the token. Without the token, docker login fails.

This is also why your ECS task needs the execution role with ECR permissions. The task is the one running docker pull behind the scenes. It needs the same kind of authentication, just done automatically through the role instead of manually through the CLI.

---

### Q17: You built a Docker image on your MacBook and pushed to ECR, but it fails to start on Fargate. What is wrong and how do you fix it?

Platform mismatch. Most MacBooks today are M1 or M2 or M3, which are ARM chips. By default Docker builds for the host architecture. So you built an ARM image. ECS Fargate runs on x86 64 by default. ARM image cannot run on x86. The task fails to start with an exec format error.

Fix is the platform flag. When you build, you specify the target platform.

docker build minus minus platform linux slash amd64 minus t your image tag dot.

This tells Docker to cross-compile for x86 64 Linux even though you are on ARM Mac. The build is a bit slower because it is emulating, but the image will run on Fargate.

There are two other fixes worth knowing.

One, you can configure Fargate to run on ARM. In your task definition, set the runtime platform to ARM 64. Now your native ARM image works. ARM Fargate is also cheaper than x86 Fargate, about 20 percent less. So if your stack supports it, this is a real cost win.

Two, multi-architecture builds with docker buildx. You can build one image that has both ARM and x86 layers. ECR stores both, and the right one gets pulled depending on the target. This is what real CI pipelines do. Build once, deploy anywhere.

The mistake people make. They build on Mac without thinking about platform, push to ECR, see it work locally, then panic when ECS fails. The error message is not always clear. Sometimes it just says exec format error or container exited immediately. If you see that, check the platform first.

---

### Q18: Mutable vs immutable image tags, which would you pick for production and why?

Immutable for production. Always.

Mutable means you can overwrite an existing tag. Push image with tag v1.0, then push another image with the same tag v1.0, the old one gets replaced. Tag now points to the new image.

Immutable means once you push a tag, you cannot overwrite it. Push v1.0 once, that is forever. You want to push again, you have to use a new tag.

Why does this matter.

With mutable tags, you lose traceability. Someone pushed v1.0 last week. Someone else pushed v1.0 today with different code. Your task definition says use v1.0. Which one is running. You do not know without checking the image digest.

Worse case. Your production deploy uses v1.0. Someone fixes a bug locally and pushes their fix as v1.0 by mistake. Now production is running their unreviewed code. No code review, no PR, just silently replaced.

With immutable tags, every deploy has a unique tag. Usually a build number or a git commit hash. v1.0.42 or main-abc1234. You can always trace what is running in production back to a specific commit. Rollback is also clean. Just point the task definition to the previous tag.

For dev and local testing, mutable is fine. You overwrite the latest tag a hundred times a day. No one cares.

For production, immutable. Set it on the repo when you create it. Force everyone to use unique tags. Build pipelines should generate the tag automatically from the git commit or build ID.

Also avoid using the latest tag in production. Latest is just a tag like any other, but it has no meaning. People overwrite it constantly. If your task definition says image colon latest, you have no idea what is running. Always pin to a specific version.

---

### Q19: How do you pull from a third-party registry like Docker Hub in an ECS task definition? What is the auth setup?

ECR is the default for AWS, but ECS can pull from anywhere. Docker Hub, GitHub Container Registry, GitLab, your own self-hosted registry. The auth pattern is the same.

Three steps.

Step one. Create a secret in Secrets Manager. The secret has two fields, username and password for the third-party registry. You store it as JSON.

Step two. In your task definition, on the container definition, there is a field called repository credentials. You put the ARN of that secret there. Now ECS knows where to find the credentials.

Step three. The task execution role needs permission to read that secret. Add a policy that allows secretsmanager get secret value on that specific ARN.

When the task starts, the execution role reads the secret, gets the username and password, uses them to log into the registry, pulls the image. All of this happens before your container starts. You see none of it.

Why use Secrets Manager and not env vars or hard-coded values. Same reason as database credentials. You do not want your credentials sitting in plaintext in the task definition JSON. The task definition might end up in git, in CloudFormation templates, in screenshots. Secrets Manager keeps them out.

One gotcha. If you are pulling a public image from Docker Hub, you do not technically need auth. But Docker Hub has rate limits for anonymous pulls. If your ECS service scales up and pulls the same image many times, you can hit the rate limit and pulls start failing. So even for public images, having Docker Hub credentials helps because authenticated pulls have a much higher rate limit.

Public ECR is the alternative for popular images. AWS hosts copies of common public images. No rate limit, no auth needed, faster pulls because they are inside AWS. If the image you need is on public ECR, prefer that over Docker Hub.

---

### Q20: What is wrong with passing database credentials as plain environment variables in an ECS task definition? How do you do it properly?

Several problems with plain env vars.

First, the credentials are in the task definition JSON. Task definition is just a config file. It ends up in your Terraform code, your CloudFormation templates, your git history. Anyone who has access to the repo has the credentials.

Second, the env vars are visible to anyone who can describe the task. Run aws ecs describe task definition, the credentials are right there in the output. You do not need access to the database, just access to ECS metadata.

Third, rotating the credentials is painful. To rotate, you need to update the task definition with the new value, create a new revision, redeploy the service. Every rotation is a deployment. Most teams just never rotate.

The proper way is Secrets Manager.

Store the database connection string in Secrets Manager. Get the secret ARN. In your task definition, instead of using value with the plain string, use valueFrom with the secret ARN. The ARN can also point to a specific key inside the secret using a path syntax.

What changes.

The credentials are not in the task definition anymore. Just an ARN that points to where they live. Anyone reading the task definition sees the ARN, not the password.

The task execution role needs permission to read that secret. So access is controlled at the IAM level, not at the config level. You can audit who has the permission.

Rotation gets easier. Update the secret value in Secrets Manager. ECS picks up the new value on the next task restart. No task definition change needed.

You can also enable automatic rotation. Secrets Manager handles rotating the secret on a schedule and updating the database password at the same time. This is the proper enterprise pattern.

For maximum compliance, you also use a customer-managed KMS key to encrypt the secret. So even AWS cannot read it without your key. But this adds operational complexity, so most teams use the default AWS-managed key for first deployment and tighten later.

---

### Q21: What IAM permissions does your task execution role need to read from Secrets Manager? Why is the task role not enough?

Two permissions on the execution role.

secretsmanager get secret value on the specific ARN of the secret.

kms decrypt on the KMS key that encrypts the secret, but only if you are using a customer-managed KMS key. For the default AWS-managed key, this is not needed.

Now why execution role and not task role.

Execution role does the setup work before your container starts. It pulls the image, creates the log group, and reads the secrets to inject them as env vars. All of this happens at task startup, before your application code is running.

Task role is for what your application does after it starts. If your app code calls Secrets Manager at runtime to read a different secret, that goes through the task role.

So if you want ECS to inject a secret into your env vars at startup, give the permission to the execution role. If your app reads secrets dynamically while running, give the permission to the task role.

For database credentials, you almost always want them injected at startup. Your app reads them as env vars. So execution role.

One more thing. The policy should be tight. Not SecretsManagerReadWrite which lets the role read every secret in the account. Use a custom policy that allows GetSecretValue on the specific secret ARN. This is least privilege. Common interview question, and it is also what auditors check for.

---

### Q22: You accidentally pushed AWS access keys to a public GitHub repo. Walk me through what happens automatically, what you do manually, and why git rm is not enough.

Three parts. Detection, automatic action, manual cleanup.

Detection happens before you push. GitHub has secret scanning enabled on all public repos by default. When you try to push code with AWS keys, GitHub detects the pattern and blocks the push. You see a message saying secret scanning found credentials. You can override and force the push if you really want, but the default blocks it.

For private repos, you need to enable secret scanning manually. Bigger orgs have it on by default. Smaller teams sometimes leave it off, which is the riskier setup.

If the push goes through, automatic action kicks in within minutes. AWS partners with GitHub. AWS detects the leaked keys, identifies which account they belong to, and applies a quarantine policy automatically. The policy is called something like AWSCompromisedKeyQuarantine. It explicitly denies almost everything those keys can do. Even though someone else might find the keys, they cannot use them.

You also get an email from AWS within minutes saying these credentials have been exposed. The email tells you to rotate them.

Manual cleanup is where people make mistakes.

First, rotate the keys. Go to IAM, delete the exposed access key, generate a new one. Anyone still using the old key gets an error.

Second, clean the git history. This is where git rm is not enough. git rm only removes the file from the current commit. The file is still there in your git history, in older commits. Anyone who clones the repo can git log and find it.

To actually remove from history, you need to rewrite the git history. The tool people use is BFG Repo-Cleaner. It scans your entire history, removes the file or the secret, and rewrites the commits. You then force-push the rewritten history to GitHub. Anyone who already cloned the repo still has the old history, but new clones get the clean version.

Third, audit what the keys did before you caught them. CloudTrail logs every API call. Check what those keys did in the time window between the leak and the rotation. If you see suspicious activity, you have a real incident on your hands.

The fix order is important. Rotate first, clean second, audit third. People often start with cleanup and forget the keys are still active in the meantime.

---

### Q23: Explain the principle of least privilege and short-lived credentials. Where does this show up in CI/CD pipelines?

Two related ideas.

Least privilege means giving credentials only the permissions they need, and nothing more. If your task only reads from S3, do not give it admin access. If your CI pipeline only deploys to ECS in one region, do not give it access to all regions.

Short-lived credentials means credentials that expire quickly. Twelve hours, one hour, sometimes one minute. The shorter the lifetime, the smaller the window if they leak.

Combined, the idea is. If credentials leak, the damage is limited because they have minimal permissions and they expire fast.

In CI/CD pipelines, this used to be a real problem.

The old way. Generate an AWS access key for your CI pipeline. Store it in GitHub Actions secrets. Every pipeline run uses these long-lived credentials. The keys never expire. If anyone gets access to your repo settings, they have permanent AWS access. If you forget about an old pipeline and never rotate the keys, they sit there forever.

The new way is OIDC. OpenID Connect. GitHub Actions has an identity provider built in. AWS has IAM identity providers. You connect them. Now when your GitHub workflow runs, GitHub generates a short-lived token saying this workflow is running in this repo on this branch. AWS trusts that token. AWS exchanges it for temporary credentials that last for the duration of the workflow run only.

The benefits.

No stored credentials in GitHub. Nothing to leak.

Credentials are tied to the specific workflow and branch. You can scope IAM policies to only allow main branch to deploy to production. PRs cannot deploy.

Credentials expire when the workflow ends. Usually fifteen minutes to an hour. Even if a leak happens, the window is tiny.

Same pattern shows up everywhere. EC2 instance roles instead of access keys on the instance. ECS task roles instead of credentials in env vars. AWS SSO for human users instead of long-lived access keys. The pattern is always the same. Identity-based access, short-lived tokens, minimal permissions.

If you are doing DevOps work in 2026 and your CI still uses stored AWS access keys, that is a red flag. Migrate to OIDC.

---

### Q24: What is aws sso login and why is it better than long-lived access keys for daily CLI use?

aws sso login is the modern way to authenticate the CLI. You run the command, it opens your browser, you log in through your identity provider, browser authentication succeeds, the CLI gets temporary credentials valid for twelve hours.

Compare to the old way. You generate a long-lived access key in IAM. You paste it into your aws credentials file. It works forever until you manually rotate it.

Why is SSO better.

First, the credentials expire. Twelve hours by default, configurable down to one hour. If your laptop gets stolen tonight, the attacker has at most twelve hours to use the credentials. With long-lived keys, they have forever.

Second, MFA is built in. Your SSO login can require MFA. Long-lived access keys can have MFA bolted on but it is awkward to use with CLI.

Third, no copy-pasting secrets. Long-lived keys end up in shell history, in scripts, in screenshots accidentally. SSO never gives you a secret to paste. The credentials live in a file the CLI manages, in a path you do not touch.

Fourth, central control. With SSO, your admin can revoke access from one place. Disable the user in the identity provider, they lose access immediately. With long-lived keys, you have to find and delete every key the user generated.

The CLI version matters. aws sso login was added in CLI version 2.32 or higher. Older versions do not have it. Run aws minus minus version to check. If you are below 2.32, upgrade.

For occasional users, this is the right pattern. For automation, you do not use sso login at all, you use OIDC or instance roles.

There is one annoying thing. SSO login expires every twelve hours. So you re-run it every morning before you start work. That is fine. Small cost for real security.

---

### Q25: Why do we put RDS in a separate subnet group from the ECS tasks? Why does RDS not need NAT or internet?

Two reasons. Isolation and zero-internet exposure.

Isolation first. Your database holds the data. The data is what matters. Everything else, your app, your task, your load balancer, can be rebuilt. The database cannot. So you keep it the most protected. Separate subnet group means database lives in its own subnets that nothing else lives in. Only thing that touches those subnets is the database.

This also lets you apply tighter network controls. The route table on the database subnet has no internet route. No NAT, no IGW. The database literally cannot reach the internet. Cannot accidentally exfiltrate data. Cannot accidentally connect to an external attacker.

Why no NAT or internet. Because the database does not need to reach out. Postgres is a service that receives connections. It does not initiate outbound calls to anything. So you do not need a path out.

But the database does need to receive connections from the app. That is the security group, not the route table. The RDS security group has an inbound rule that allows the ECS security group on port 5432. That is the only way in.

So the layered model is.

App subnet has NAT and IGW path. App tasks need to pull images from ECR, call external APIs, send emails. They need internet.

Database subnet has no internet at all. Pure private. No way to reach out, no way for the internet to reach in.

This is also why people miss it. They put RDS and ECS in the same subnets to save effort. It works. The app can talk to the database. But you have broken the isolation. If your app gets compromised, the attacker is on the same subnet as the database with no extra hop.

Proper production layout is always three tiers of subnets. Public for ALB. Private app for ECS. Private isolated for RDS. Always.

---

### Q26: Walk me through the security group chain for ALB to ECS to RDS. Why three groups instead of one big one?

Three security groups. Each one only allows what is needed.

ALB security group. Inbound rule. Allow 443 from 0.0.0.0/0. Maybe 80 also for HTTP redirect. The internet talks to your ALB. So source is anywhere.

ECS security group. Inbound rule. Allow the app port, usually 8000, but source is the ALB security group. Not 0.0.0.0/0. The ECS tasks should only accept traffic from the ALB. Nothing else. So you reference the ALB security group as the source.

RDS security group. Inbound rule. Allow port 5432, source is the ECS security group. The database should only accept traffic from the ECS tasks. Not from the ALB, not from your laptop, not from the internet. Only from the ECS tasks.

This is the chain. ALB to ECS, ECS to RDS. Each link is tight.

Why three groups and not one big one.

If you put everything in one security group with a bunch of rules, you cannot enforce direction. Any resource in that group can talk to any other resource in that group on the allowed ports. The ALB could talk directly to the database. A misconfigured task could expose itself to the internet. The blast radius is much bigger.

With three separate groups, each link is explicit. If you have a bug somewhere, it cannot accidentally break isolation. The ALB cannot talk to the database because there is no rule saying ALB security group can reach 5432.

Security group references are the trick. You do not hardcode IPs. You reference the other security group by ID. So as tasks come and go, as IPs change, the rule still works because it follows the group, not the IP.

Auditors love this pattern. Each rule is purposeful. You can explain why every rule exists. With one big group, you cannot.

In Terraform code, this is also cleaner. Three modules, three groups, each one references the others. No mess of inline rules.

This is the pattern for every multi-tier app on AWS. Public to app, app to data. Three groups, three layers, chain them together with references.

---

### Q27: Can you run a stateful database in a container? When would you do this vs using RDS?

Yes you can. People used to think containers cannot run databases. That is wrong. Modern setups run Postgres, MySQL, MongoDB, even Cassandra in containers all the time. Big companies do it. Netflix, Uber, others.

The way you make a container stateful is volumes. The container itself is ephemeral. When it dies, anything in its filesystem is gone. But you mount a persistent volume into the container. The volume lives longer than the container. New container starts, mounts the same volume, picks up where the old one left off.

For ECS, the volume is usually EFS. EFS is shared filesystem, works across AZs, survives task restarts. You mount EFS at the path where Postgres stores its data, slash var slash lib slash postgresql slash data. Task dies, new task starts, EFS is still there with all the data.

For Kubernetes the same pattern uses persistent volumes through CSI drivers, often EBS or EFS underneath.

Now when do you do this versus just using RDS.

Use RDS when. You want managed everything. Automatic backups, automatic patching, point-in-time recovery, read replicas, failover, all of that for free. You do not have a DBA on your team. You are okay paying the RDS price tag, which is usually higher than running it yourself.

Use database in container when. You want full control over the database version, the config, the storage. You have a team that knows how to operate databases. You want to save money at scale. You want to use a database that AWS does not offer as a managed service.

Real example. Companies running Postgres at massive scale often run it in Kubernetes with CloudNativePG operator. They get features that RDS does not have. Custom replication topology, write scaling through multiple primaries, exact control over WAL archiving. Managed RDS cannot do this.

For most companies, RDS is the right call. The price is worth not thinking about it. For specialized needs or huge scale, containerized databases win.

There is a middle option too. Aurora Serverless. Managed Postgres or MySQL that scales to zero when not in use. Cheaper than regular RDS for low-traffic workloads. Worth knowing about.

---

### Q28: Explain rolling vs blue green deployment in ECS. How would you implement blue green using ALB and target groups?

Two deployment strategies. Different tradeoffs.

Rolling is the default in ECS. You push a new task definition. ECS slowly replaces old tasks with new ones. Usually it brings up one new task, waits for it to be healthy, kills one old task, brings up the next, and so on. At any moment, some old tasks and some new tasks are running together. Traffic gets split across both.

The good thing. Simple. No extra infrastructure. Built into ECS.

The bad thing. If the new version has a bug, some users hit the bug while you roll back. The rollback also takes time because you have to replace tasks again. And you cannot easily run any final verification before traffic hits the new version.

Blue green is different. Blue is your current live version. Green is the new version. You bring up green completely in parallel, fully running, no traffic yet. You run smoke tests. When you are happy, you flip all traffic from blue to green in one shot. Blue is still there but idle. If something goes wrong, you flip back instantly.

The good thing. Instant rollback. No version mixing. Full verification before traffic switch.

The bad thing. Twice the infrastructure during the switch. More complex to set up.

How do you implement blue green with ALB.

You have two target groups. tg-blue and tg-green. Two ECS services, one registered with each target group. Both services run the same number of tasks, but they run different versions of the app.

The ALB listener has a rule that forwards traffic to one of the target groups. Say it currently forwards to tg-blue. That is where 100 percent of traffic goes.

To deploy. You update the ECS service connected to tg-green with the new task definition. ECS replaces all tasks in the green service with the new version. Green is now ready but no traffic.

You run smoke tests against the green target group directly. Hit the targets through the load balancer with a special header, or use a second listener on a different port that points only to green. Verify the new version works.

When happy. You change the listener rule. Forward to tg-green instead of tg-blue. Traffic switches instantly. Users start hitting the new version.

If anything is wrong. Change the rule back to tg-blue. Traffic switches back instantly. Zero downtime, zero data loss.

After some time, you scale down the blue service to zero. Next deployment, you reverse the roles. Green becomes the current live, blue becomes the new deployment target.

AWS has CodeDeploy that does this for you with ECS. Configure once, every deploy follows the blue green pattern. Worth knowing about but the underlying mechanism is just two target groups and listener rule changes.

---

# Interview Q&A: ECS, ECR, ALB, Containers in Production

## Batch 3: Autoscaling, Patterns, Debugging, Cost, Behavioral (Q29-40)

---

### Q29: What metrics can ECS autoscaling use by default? How would you autoscale on a custom metric like SQS queue depth?

ECS gives you three default metrics. CPU utilization, memory utilization, and ALB request count per target.

CPU and memory are obvious. If average CPU across the service goes above a threshold, scale out. If it drops, scale in.

ALB request count per target is the smart one. It looks at how many requests each task is handling. If your tasks are getting too many requests, scale out. This is often better than CPU because some apps are not CPU-bound but still need more replicas under load.

For target tracking, you set a target value like 50 percent CPU or 100 requests per task, and ECS keeps the service close to that number.

Now custom metrics. The default three are not enough for every use case.

Real example. You have a worker service that processes messages from an SQS queue. CPU and memory might be low even when the queue is huge. So scaling on CPU is wrong. You want to scale based on queue depth.

How to do it.

CloudWatch already publishes SQS metrics by default. You get ApproximateNumberOfMessagesVisible for every queue. That is your signal.

Create a CloudWatch alarm based on that metric. Say the alarm fires when queue depth goes above 1000.

In ECS, add a scaling policy of type step scaling, not target tracking. Step scaling lets you connect an external CloudWatch alarm. Point the policy at your alarm.

Define the steps. If queue depth is 1000 to 5000, add 2 tasks. If queue depth is over 5000, add 5 tasks. If queue depth drops below 100, remove tasks.

Same pattern works for any CloudWatch metric. Custom application metric that you publish yourself, S3 bucket size, DynamoDB throttling errors. Anything that has a CloudWatch metric can drive ECS scaling.

For very advanced setups people use Application Auto Scaling APIs directly or use Lambda functions to trigger scaling based on logic CloudWatch cannot express.

The takeaway. Three defaults are fine for web apps. Custom metrics through CloudWatch alarms are how you handle workers and async jobs. Pick the metric that actually reflects load, not the easiest one to set up.

---

### Q30: Why should scale in cooldown be longer than scale out cooldown?

Different costs of being wrong in each direction.

Scale out is cheap to be wrong about. You add a task. Worst case, you have one extra task running for a few minutes. Small cost. So you want scale out to be aggressive. Quick to respond. 60 seconds is fine.

Scale in is expensive to be wrong about. You remove a task. If load comes back, you do not have capacity to handle it. Users see latency or errors while ECS spins up a new task, which takes 30 to 60 seconds. So you want scale in to be conservative. Wait longer before removing a task. 300 seconds, five minutes, is reasonable.

The other reason is preventing thrashing. Imagine your CPU bounces between 45 percent and 55 percent over five minutes. With short cooldowns in both directions, you would scale out when it hits 55, then scale in 30 seconds later when it hits 45, then scale out again. Tasks are constantly being created and killed. This is called flapping. It is bad for performance and bad for any stateful caching in your tasks.

Longer scale in cooldown smooths this out. Even if CPU dips for a minute, you do not remove a task. Only if it stays low for the full cooldown period do you scale in. Real sustained low load triggers scale in. Brief dips do not.

Common pattern. Scale out cooldown 60 seconds. Scale in cooldown 300 seconds, sometimes 600. Tune based on how long your tasks take to start. Slower-starting apps need more conservative scale in.

This applies to any autoscaler. ECS, EKS, EC2 autoscaling groups, Lambda concurrency, all of them. Asymmetric cooldowns are the rule.

---

### Q31: When would you put more than one container in a single ECS task? Explain the sidecar, init container, proxy, and adapter patterns with real use cases.

Single container per task is the default. But sometimes you need helpers running alongside your main app. That is when you put multiple containers in one task.

The key thing about multiple containers in one task. They share the same network and storage. They can talk to each other on localhost. They live and die together. Different from running two separate services.

Four patterns to know.

Sidecar pattern. A helper container runs next to your main app and adds functionality without changing the app code. Classic example. Your app writes logs to a file inside the container. A sidecar container watches that file and ships the logs to a logging service. The app does not know the sidecar exists. The app stays focused on business logic. The sidecar handles infrastructure concerns.

Other sidecar examples. Service mesh proxies like Envoy. Secret rotation agents that refresh credentials on the filesystem. Backup agents that snapshot data periodically.

Init container pattern. A container that runs once at the start of the task, does some setup work, then exits before the main container starts. ECS waits for the init container to finish successfully before starting the main one.

Use cases. Run database migrations before the app starts. Wait for the database to become available. Pre-fetch configuration files from S3. Set file permissions on a mounted volume.

The pattern is. Main app starts cleanly because the environment is already prepared. Without init, you would have to bake all this setup into the app startup code, which is messy.

Proxy pattern. A container that sits in front of your main container and handles networking or routing. Nginx as a reverse proxy in front of a Flask app. Envoy doing TLS termination. A custom proxy that adds authentication headers before the request reaches the app.

The app talks plain HTTP. The proxy adds HTTPS, auth, rate limiting, all of it. App code stays simple.

Adapter pattern. A container that translates between the format your main app speaks and the format some other system expects. Your app emits metrics in Prometheus format. The adapter scrapes those metrics and pushes them to Datadog. Or your app writes logs in one format and the adapter converts them to another format before shipping.

Adapter is similar to sidecar, but the focus is format translation, not adding new behavior.

When you go to Kubernetes, the same four patterns apply. Pods are exactly this. Multiple containers in one pod sharing network and storage. The terminology and the design carries over directly. If you understand it for ECS, you understand it for Kubernetes.

Interviewer follow-up usually is. Can you give me a concrete project where you used one of these. Have one ready. Logging sidecar, init container running migrations, nginx proxy for SSL. Any of these are common in real DevOps work.

---

### Q32: Why is Docker Compose not used in production? Where does it fit in a real workflow?

Three reasons Compose is not production.

No self-healing. If your container dies in Compose, it just sits there dead. There is a restart policy, but it is dumb. It restarts on the same machine, no matter what. If the machine is failing, the container keeps dying. Compose does not move it elsewhere, does not look at health, does not understand failure modes. ECS or Kubernetes does all of this.

No horizontal scaling. Compose runs on one machine. You cannot easily scale a service across multiple machines. There is docker compose scale, but it just runs more containers on the same host. If your host runs out of capacity, you are stuck. ECS scales tasks across multiple hosts and AZs automatically.

No production observability. Compose does not integrate with cloud logging, monitoring, alerting out of the box. You have to bolt all of that on. ECS gets you CloudWatch integration, ALB metrics, target group health for free.

Where does Compose fit then.

Local development. This is the main use case. You are a developer working on a microservices app. You need Postgres, Redis, your app, and a worker all running together on your laptop. Docker Compose spins them up with one command. You debug, you change code, you restart. Compose is perfect for this.

Testing environments. CI pipelines often use Compose to spin up a full stack for integration tests. Tests run against the stack, then everything gets torn down. Quick, clean, reproducible.

Demos and prototypes. You want to show someone an idea. Compose file gets the whole thing running in two minutes. No cloud, no cost, no setup.

Learning. Same reason you learn it in this bootcamp. Compose forces you to think about services, dependencies, networking, volumes, all the concepts that show up in Kubernetes and ECS. If you understand Compose well, the jump to Kubernetes is much smaller.

The pattern is. Compose for local. ECS or Kubernetes for production. Different tools, different jobs. People who try to run Compose in production usually end up rebuilding things ECS already has, badly.

---

### Q33: Why is creating the CloudWatch log group before the ECS task definition important? What error do you get if you skip this?

When ECS starts a task with awslogs driver configured, the task tries to write logs to a specific log group. If the log group does not exist, the task tries to create it. Sometimes this works. Sometimes it does not, especially the first time.

The error you see is ResourceInitializationError with a message about CloudWatch logs. The task goes to STOPPED state. You look at the task in the console, you see the cryptic error, and you spend time troubleshooting.

In my class I hit this live. The task was failing not because of NAT or networking, but because the log group did not exist yet. Creating the log group manually first fixed it.

There are two ways to handle this.

One. Pre-create the log group manually before you create the task definition. Go to CloudWatch console, create log group with the exact name you will reference in the task definition. This is the safe pattern.

Two. Tell the task definition to auto-create the log group. There is a flag called awslogs-create-group set to true. ECS will create the log group on first run if it does not exist. This works but you need the execution role to have CreateLogGroup permission, not just CreateLogStream.

The recommendation is pre-create. Reasons.

You control the retention setting. Auto-created log groups have no retention by default, which means logs live forever and your CloudWatch bill grows forever. Pre-create with a retention of 7 days or 30 days.

You can apply tags from the start. Cost tracking tags, environment tags, owner tags. Auto-create skips this.

The IAM permission is tighter. CreateLogStream is enough if the log group exists. CreateLogGroup is a broader permission you do not really need.

In Terraform, you create the log group as a separate resource, then reference it in the task definition. The task definition depends on the log group. Order is guaranteed.

This is one of those small things that nobody teaches but every production deployment needs. Pre-create the log group. Always.

---

### Q34: An ECS task fails to start. What is your debugging order, what do you check first, second, third?

Six steps in order. Stop early as soon as you find the issue.

Step one. Look at the task status. ECS console, go to the service, click tasks, find the failed task. Status will be STOPPED with a reason. Read it. Sometimes the reason is obvious. CannotPullContainerError, ResourceInitializationError, EssentialContainerExited. The reason narrows the problem immediately.

Step two. Check the task logs in CloudWatch. If the container started at all, even briefly, it likely wrote logs. Look at the log group for this task. Sometimes the app crashed because of a missing env var, bad database connection, syntax error. Logs tell you immediately.

If there are no logs at all, the task never reached the point of running your app. The problem is earlier. Image pull, log group setup, secrets, or networking.

Step three. ECR pull failure. If logs show CannotPullContainerError, your task cannot reach ECR. Check the NAT gateway is up. Check the route table for private subnets has a route to NAT. Check the security group on the task allows outbound traffic on port 443. Check the image URI in the task definition is correct.

Step four. Log group. If error says ResourceInitializationError with CloudWatch logs, the log group does not exist or the execution role cannot write to it. Pre-create the log group, attach the right policy to the execution role.

Step five. Secrets. If the error is about secrets, the execution role lacks Secrets Manager permission. Check the role has secretsmanager get secret value on that specific ARN. Also check the secret ARN in the task definition is correct, including the colon-key-colon-version syntax if you reference a specific key inside the secret.

Step six. Networking. The task starts and runs but the ALB shows it unhealthy. This is past the start, this is connectivity. Check the ALB security group allows outbound on the task port. Check the task security group allows inbound on the task port from the ALB security group. Check the health check path returns 200.

Most failures are in steps three through five. Image pull, log group, or secrets. They look mysterious in the UI but the root cause is almost always one of those three.

Tip. AWS error messages can be misleading. The displayed error is sometimes the second-order effect, not the root cause. Always read the full task event log, not just the summary. The full event log shows the chain of failures in order.

---

### Q35: Your team has 50 EC2 instances and you suspect most are idle. How would you prove it and convince leadership to right-size? What AWS tools help?

Step one. Get the data. Numbers convince people, not opinions.

CloudWatch already has metrics for every EC2 instance. CPU utilization, network in and out, disk reads and writes. Pull the last 30 days of CPU utilization for all 50 instances. If most are sitting under 10 percent average, you have a strong case.

For memory and disk, you need the CloudWatch agent installed on the instances. If it is, you get those metrics too. If not, push for it as a first improvement.

Tools that make this easier.

AWS Compute Optimizer. This is the tool built for exactly this. Compute Optimizer analyzes your EC2 utilization over weeks and gives recommendations. Downsize this instance from m5.xlarge to m5.large. Save this much per month. It does the math for you. You enable it once and within a few days you have a full report.

AWS Trusted Advisor. Broader cost optimization tool. Looks for idle EC2, underutilized EBS, RDS not in use, all of that. Trusted Advisor is good for the broad sweep. Compute Optimizer is good for the specific EC2 rightsizing.

Cost Explorer. Shows you the actual spending over time. Filter by instance, by tag, by service. You can see which instances cost the most and start there.

Step two. Translate to money. Engineers care about CPU percentage. Leadership cares about dollars. Take the Compute Optimizer recommendations and compute the monthly savings.

Example pitch. We have 50 instances. Compute Optimizer recommends right-sizing 30 of them. Estimated monthly saving is 8000 dollars. Annual saving 96 thousand. Implementation effort is two weeks of one engineer.

Now leadership has a number. ROI is clear. Decision becomes easy.

Step three. Show the risk. Right-sizing can break things if done blindly. Some workloads spike during specific hours, month-end, or quarter close. The 30-day average might be 10 percent but the peak might be 80. Right-size to that, you crash during peak.

So your plan should include. Right-size in dev and staging first. Watch for one week. Then move to production. Have a rollback path.

Step four. Cover the broader cost picture. While you are at it, mention. Idle EBS volumes that are not attached. Old snapshots nobody uses. Unattached elastic IPs that still cost money. NAT gateways in regions with no traffic. Reserved Instances or Savings Plans for predictable workloads. The right-sizing exercise often uncovers more cost than just EC2.

Bigger lesson. Cost optimization is a continuous practice, not a one-time project. Set up monthly reviews. Have CloudWatch alarms on cost anomalies. Make the team aware that idle resources cost real money.

---

### Q36: NAT gateway vs VPC endpoints, when does each make sense from a cost standpoint?

Two cost structures to compare.

NAT gateway. You pay a flat hourly charge plus per-GB data processing. Roughly 32 dollars per month for the hourly piece, plus a few cents per GB. Real cost depends on your data volume. If you pull a lot of large images and send a lot of traffic, the data charges add up.

VPC endpoints. Two types matter. Gateway endpoints for S3 and DynamoDB are free. Interface endpoints for everything else have a flat hourly charge plus per-GB. Hourly charge per endpoint is roughly 7 dollars per month per AZ. So an interface endpoint across 3 AZs is 21 dollars per month before any data charges.

Single endpoint sounds cheaper than NAT. But here is the catch. You need multiple endpoints to replace one NAT.

For ECS alone you typically need. ECR API endpoint. ECR DKR endpoint. CloudWatch Logs endpoint. S3 gateway endpoint, which is free. So three interface endpoints across 3 AZs is 63 dollars per month minimum.

That is already more than one NAT gateway.

If you also have apps calling other AWS services, you keep adding endpoints. Secrets Manager endpoint. SSM endpoint. KMS endpoint. SNS endpoint. SQS endpoint. Each one is another monthly charge.

Where does each one win.

NAT gateway wins for. Small to medium deployments with low data volume. Workloads that talk to many different AWS services. Workloads that also need to reach the public internet for non-AWS APIs. Simpler setup, one thing to manage.

VPC endpoints win for. High-data workloads where you save real money on data transfer. Strict compliance environments where traffic must stay on AWS network. Setups where you only talk to a few specific AWS services.

There is a hybrid pattern too. Use NAT for general internet access, but add VPC endpoints for the high-volume services you use most. S3 gateway endpoint is always worth adding because it is free and reduces NAT data transfer. ECR endpoints can save real money if you pull large images frequently.

The general rule. For most teams, start with NAT. It is simpler and cheaper at low scale. If your data volume grows or you have compliance needs, add VPC endpoints selectively for the heaviest services. Do not blindly create endpoints for everything.

---

### Q37: How would you reduce cost on Jenkins build servers that run 24 7 but only have jobs during office hours?

Several options. From simple to advanced.

Simplest option. Lambda to start and stop EC2 instances on a schedule. Write a small Lambda that starts the Jenkins instance at 8 AM Monday through Friday, and stops it at 8 PM. Schedule it with EventBridge. Now the instance only runs during work hours. Costs drop by roughly 70 percent. Almost zero effort.

The risk. If someone needs to run a build at midnight, the server is off. Easy fix. Add a manual trigger. Slack command or button on a dashboard that starts the instance on demand.

Better option. EC2 plugin for Jenkins. There is a plugin called Cloud or EC2 Fleet that lets Jenkins itself manage EC2 build agents. Master Jenkins stays small and always-on. When a job is triggered, the plugin spins up an EC2 worker to run the job. When the job ends, the worker terminates.

The benefit. Workers only exist when jobs need them. If no jobs are running, no workers, no cost. If many jobs run at once, many workers spin up in parallel. Auto-scaling builds.

You can also configure idle time. Keep workers around for 30 minutes after the last job finishes, so if another job comes in soon, it reuses the worker instead of waiting for a new spin-up.

Even better option. Move to managed CI like GitHub Actions or AWS CodeBuild. These services charge only for actual job runtime. You do not manage any servers. GitHub Actions has free runtime for open source and very cheap minutes for private repos. CodeBuild is pay-per-minute, no idle cost.

For many teams this is the right destination. Run Jenkins for legacy jobs that cannot move, but new pipelines go to managed CI.

Mid-step option. Spot instances. If your jobs can tolerate interruption, use Spot instances for build workers. 70 to 90 percent cheaper than on-demand. The risk is the spot instance can get reclaimed mid-build. For builds that take less than 10 minutes, the risk is acceptable. For long builds, you want a fallback to on-demand.

How to convince leadership.

Same as the right-sizing question. Get the data. Pull current Jenkins costs from Cost Explorer. Compute the saving. Show the rollback path. Show the implementation timeline.

If your Jenkins server costs 500 dollars a month and you can drop it to 100 by running only during work hours, that is 4800 dollars a year. Roll out plan. Test schedule shutdown in staging Jenkins first. Then production with a manual override for after-hours needs. Then monitor for a month before declaring done.

Bigger principle. Anywhere you have idle resources, you have potential savings. Build servers, dev databases, staging environments. They do not all need to run 24 7. Most of them can be turned off when not in use.

---

### Q38: Walk me through a production deployment you owned end to end. What broke? What did you fix? What would you do differently?

This question is asking for a real story with context, decisions, and lessons. Have one ready. Pick a project you actually did and remember well.

Here is the framework you should follow when answering.

Start with the context. What was the project. Why were we doing it. What was at stake. Who were the users. Skip company-specific jargon and explain like the interviewer has no context.

Move to the architecture. What did you build. What technology stack. Why those choices. What were the constraints.

Then the work. Walk through how you delivered it. Phases, milestones, what shipped when.

Now the interesting part. What broke. This is what they really want to hear. Some examples that work.

The deployment caused an outage because we had no rollback plan. Users could not access the system for 45 minutes. We rolled back manually by reverting the Terraform state and force-deploying the previous task definition. Took longer than it should have because we had not practiced.

We hit unexpected scale. Our autoscaling did not respond fast enough to a marketing campaign that drove ten times normal traffic. ALB returned 503s for 20 minutes while ECS slowly added tasks. We had to manually scale and then redesign the scaling policy with shorter cooldowns and lower CPU target.

A bug in the new version showed up only under real production load. We did not catch it because our staging environment was a tenth of the size. The bug caused database connection pool exhaustion. We rolled back and spent a week fixing the connection pooling.

Whatever the breakage, be honest about it. Interviewers respect engineers who own failures, not engineers who pretend everything went perfectly.

Then. What would you do differently.

Better staging environment that matches production scale.
Automated rollback in the deployment pipeline.
Game days where we practice failure scenarios before they happen for real.
Better observability before deploying. SLOs defined, dashboards built, alerts wired in advance.
Smaller deployments. We tried to ship too much in one release. Now we deploy smaller pieces more often.

This is the answer that gets you hired. Not because nothing went wrong, but because you learned from what did.

If you have nothing to share. That is also a question to think about. Pick anything you have built. A bootcamp project. A learning project. A side project. Apply the same framework. Context, architecture, work, what broke, lessons. Even a non-production project can show how you think.

---

### Q39: How do you decide when to use a managed AWS service vs running it yourself?

Three factors. Convenience, control, cost.

Convenience favors managed. AWS does the patching, the backups, the scaling, the failover. You focus on building your app. For most teams, this is the right tradeoff. Your engineers are expensive. Their time on infrastructure plumbing is wasted unless that is your business.

Control favors self-managed. Managed services are opinionated. RDS Postgres exposes the database but not the underlying OS. You cannot install custom extensions. You cannot tune some parameters. If you need full control over a specific knob, you have to run it yourself.

Cost depends on scale. Managed services are cheaper at small scale because you pay no engineering time. Self-managed becomes cheaper at large scale because the engineering time amortizes across more usage. Spotify or Netflix running their own Cassandra clusters on EC2 is cheaper than them using DynamoDB. For most companies, the breakeven is far away.

How to decide for a specific service.

Ask. Does the managed version do what we need. If yes, use it. If it is missing a specific feature you need, you have two choices. Work around the limitation, or run it yourself for that one piece.

Ask. What is the cost difference. Sometimes managed is twice the price. If you save one engineer of operational work, it is still cheaper. Engineering time is more expensive than AWS bills at most companies.

Ask. What is the failure mode. If the managed service fails, what happens. Usually AWS handles failover automatically. You just see brief unavailability. If self-managed fails, you are paged at 2 AM. The on-call cost matters.

Ask. Are we locked in. Managed services tie you to AWS. RDS Postgres still talks Postgres protocol, so the lock-in is mild. DynamoDB is more lock-in. If multi-cloud is important to your business, managed services with proprietary APIs are riskier.

My usual rule. Default to managed. Move to self-managed when you have a specific reason. Cost at scale, feature you cannot get otherwise, compliance need.

For databases. RDS or Aurora unless you have a real reason. The price is worth it.

For containers. ECS or EKS, not raw Docker on EC2. Both are managed enough.

For load balancing. ALB or NLB. Nobody runs their own load balancer anymore.

For secrets. Secrets Manager or Parameter Store. Do not roll your own.

The companies that successfully run things themselves at scale have specialized teams for it. Database SRE teams, networking teams, security teams. If you do not have that, use the managed version.

---

### Q40: Tell me about a time you had to debug a problem where the error message was misleading. How did you approach it?

Like the previous behavioral, you need a real story. Have one or two ready.

Pattern of a good answer. Describe the situation. The error you saw. Why it was misleading. How you found the real cause. What you learned.

An example from the class I just taught.

The situation. We deployed an ECS service. Tasks were failing. The error in the console was ResourceInitializationError with a message about CloudWatch logs. We thought the log group was the problem.

What we tried first. Recreated the log group manually. Same error.

Deeper look. Watched the task event log carefully. Read the full message. The error mentioned CloudWatch logs but the underlying issue was actually that the task could not reach the internet to pull the image. The CloudWatch error was a side effect because the task tried to write its startup logs while still failing on image pull.

What we did. Configured the NAT gateway route to the private subnets. Task started successfully on the next attempt.

The lesson. Cloud error messages often surface the second-order failure, not the root cause. The displayed error is the last thing that went wrong, not the first.

How I changed my approach. Always look at the full event log, in time order, not just the summary error. The earlier events tell you the actual root cause. The later events are just consequences.

Another good story.

The situation. Application was getting 502 from ALB intermittently. Maybe one in 20 requests. CPU and memory looked fine. Logs looked fine.

What I tried. Restarted the tasks. Problem persisted. Increased the task count. Problem persisted. Looked at access logs. Saw the 502s but no useful info.

Deeper look. Found that the ALB health check was hitting tasks that were being recycled. ECS deployment was killing tasks before draining connections cleanly. New requests landed on dying tasks for a brief window during deployment.

The fix. Configured deregistration delay on the target group to give in-flight requests time to finish before killing tasks. Set graceful shutdown handling in the app to drain connections properly. The 502s stopped.

The lesson. Intermittent errors during deployment usually point to lifecycle issues, not application bugs. Look at deployment timing, not application code.

The general principle to communicate.

When error messages are misleading, do not stay on the first hypothesis. Read everything. Look at timing. Look at context. The error message tells you something is wrong, not what is wrong. Treat it as a clue, not the answer.

Bonus. Mention that you write postmortems after incidents like this. Capture the misleading error and the real cause. Next time someone on the team sees the same error, they find the postmortem and skip the rabbit hole you went down.

This is what interviewers really care about. Not that you can debug. That you can systematically improve over time and prevent the same problem from happening again.
