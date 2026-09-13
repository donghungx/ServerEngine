function template() {
    return {
        id: "svelte",
        title: "Svelte",
        icon: "../icons/projects/svelte.svg",
        description: "Svelte app for fast local development.",
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
