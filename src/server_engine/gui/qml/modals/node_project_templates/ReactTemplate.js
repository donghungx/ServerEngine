function template() {
    return {
        id: "react",
        title: "React",
        icon: "../icons/projects/react.svg",
        description: "React app for a local domain.",
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
