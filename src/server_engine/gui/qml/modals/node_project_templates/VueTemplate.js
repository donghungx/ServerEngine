function template() {
    return {
        id: "vue",
        title: "Vue",
        icon: "../icons/projects/vue.svg",
        description: "Vue app for local development.",
        runtimeType: "frontend",
        minNodeVersion: "18.0.0",
        recommendedNodeVersion: "20.0.0",
        installCommand: "npm install",
        createCommand: "npm create vite@latest",
        devCommand: "npm run dev",
        buildCommand: "npm run build",
        defaultPort: "5173"
    }
}
