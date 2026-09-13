function template() {
    return {
        id: "remix",
        title: "Remix",
        icon: "../icons/projects/remix.svg",
        description: "Remix app with server rendering.",
        runtimeType: "fullstack",
        minNodeVersion: "18.18.0",
        recommendedNodeVersion: "20.0.0",
        installCommand: "npm install",
        createCommand: "npx create-remix@latest",
        devCommand: "npm run dev",
        buildCommand: "npm run build",
        defaultPort: "3000"
    }
}
