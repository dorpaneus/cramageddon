# 🚀 Terraform Associate Exam - 7-Day Accelerated Study Plan

## Target Audience:
Professionals with a background in Infrastructure as Code (IaC), particularly **Ansible**.

## Goal:
Achieve readiness for the Terraform Associate exam in approximately 21-35 hours of focused study (3-5 hours/day).

---

## 📅 Daily Study Breakdown

### Day 1: 🏗️ Fundamentals & HCL Deep Dive

| Focus Area | Key Activities | Lab Practice |
| :--- | :--- | :--- |
| **Terraform Workflow** | Understand the core commands: `init`, `plan`, `apply`, `destroy`, `fmt`. | Initialize a basic AWS/Azure/GCP Provider. Run the full workflow on a single resource. |
| **HCL Syntax** | Review resource blocks, provider blocks, variables (`variable`, `local`, `output`). | Practice setting up environment variables for credentials and using input variables. |
| **Exam Domain 1** | Understand Infrastructure as Code (IaC) concepts. | Write a basic `.tf` file and understand the different block types. |

### Day 2: 💾 The Critical Difference: State Management

| Focus Area | Key Activities | Lab Practice |
| :--- | :--- | :--- |
| **State File** | **Master this concept.** Understand the purpose of `terraform.tfstate`. | Manually inspect the state file after an `apply`. Run `terraform show`. |
| **State Commands** | Learn `import`, `taint`, `untaint`, and `state mv`. (Common exam questions). | Practice using `terraform import` to bring an existing resource into your state. Use `terraform taint`. |
| **Remote Backends** | Understand why remote state (S3, Azure Blob, etc.) is necessary for team environments and **state locking**.  | Configure a **remote backend** and rerun your workflow. Verify state locking. |

### Day 3: 🛠️ Configuration & Resource Dependencies

| Focus Area | Key Activities | Lab Practice |
| :--- | :--- | :--- |
| **Resource Dependencies** | Understand explicit (`depends_on`) and implicit dependencies. | Create two resources where one needs an attribute from the other (e.g., a security group ID for a VM) to test implicit dependency. |
| **Data Sources** | Learn to fetch existing infrastructure details using `data` blocks. | Use a `data` source (e.g., fetching a VPC ID) to reference unmanaged infrastructure. |
| **Loops & Conditionals** | Review `count`, `for_each`, and conditional expressions (`? :`). | Use `count` for multiple identical resources and `for_each` for resources based on a complex map variable. |

### Day 4: 📦 Modules & Code Organization

| Focus Area | Key Activities | Lab Practice |
| :--- | :--- | :--- |
| **Module Basics** | Understand module sources (local, registry, Git) and inputs/outputs. | Convert your basic configuration into a reusable local **Module**. |
| **Workspaces** | Learn the purpose of `terraform workspace` (and why it's generally discouraged in favor of folders/state files). | Use `terraform workspace new staging` and `terraform workspace select default`. |
| **Providers** | Review how providers are configured, versioned, and downloaded. | Experiment with different provider versions by adjusting the `required_providers` block. |

### Day 5: ☁️ Provisioners, Backends, and Terraform Cloud

| Focus Area | Key Activities | Lab Practice |
| :--- | :--- | :--- |
| **Provisioners** | Understand `local-exec` and `remote-exec`. **Remember: Terraform provisions, Provisioners configure.** | Use a `local-exec` provisioner to run a local script after resource creation. |
| **CLI Settings** | Review `override` files, `tfrvars`, and other non-HCL ways to affect configuration. | Use a `.tfvars` file to pass complex variable values into your configuration. |
| **HCP Terraform (Cloud/Enterprise)** | Review key features: Remote operations, Sentinel, Cost Estimation, and private module registry. | Focus on **terminology** for the exam. |

### Day 6: 📝 Practice Exam Simulation 1

| Focus Area | Key Activities |
| :--- | :--- |
| **Full Practice Exam** | Take a timed, full-length practice exam. |
| **Review Mistakes** | Go through every missed question. Find the **official HashiCorp documentation** that confirms the correct answer for maximum reinforcement. |

### Day 7: 📚 Final Review & Practice Exam 2

| Focus Area | Key Activities |
| :--- | :--- |
| **Targeted Review** | Focus solely on the domains/topics where you scored lowest on Day 6 (often **State Management** and **HCL Functions/Expressions**). |
| **Practice Exam 2** | Take a second full-length practice exam. Aim for a score above **80%**. |
| **Mental Prep** | Review exam rules, environment, and logistics. Get ready to pass! |

---

## ✅ Key Takeaways for Ansible Users

* **Mindset Shift:** Terraform is **Declarative** and manages the **Infrastructure**. Ansible is often **Procedural** and manages the **Configuration**.
* **The State:** The Terraform State file is the single most important concept unique to Terraform; master its use, its commands, and remote backends.
