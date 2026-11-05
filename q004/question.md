# Task: Install Argo CD with Helm and CRD Management

**Context:**
Ensure you are operating in the `default` cluster context.

**Target Namespace:**
`argocd`

**Scenario:**
The cluster administrators have already pre-installed the Argo CD CustomResourceDefinitions (CRDs) into the cluster. You are tasked with preparing the deployment manifest template and deploying Argo CD using Helm without reinstalling or duplicating CRD management.

**Requirements:**
1. Add the official Argo CD Helm repository named `argo` using URL `https://argoproj.github.io/argo-helm`. Ensure your local repository cache is updated.

2. Verify that the Argo CD CRDs are already pre-installed in the cluster.

3. Generate a Helm template of the Argo CD Helm chart:
   - Repository/Chart: `argo/argo-cd`
   - Chart Version: `7.7.3`
   - Namespace: `argocd`
   - Release name: `argocd`
   - Configuration: Configure the chart to not install CRDs.
   - Save the rendered template output directly to `/argo-helm.yaml`.

4. Install Argo CD using Helm into the cluster:
   - Release name: `argocd`
   - Namespace: `argocd`
   - Chart Version: `7.7.3`
   - Configuration: Use the same configuration as used in the template (do not install CRDs).

*Note: You do not need to configure ingress or external access to the Argo CD server UI.*
