function template() {
    return {
        id: "nuxt",
        title: "Nuxt",
        icon: "../icons/projects/nuxt.svg",
        description: "Nuxt app with local rendering.",
        runtimeType: "fullstack",
        minNodeVersion: "18.18.0",
        recommendedNodeVersion: "20.0.0",
        installCommand: "npm install",
        createCommand: "npx nuxi@latest init",
        devCommand: "npm run dev",
        buildCommand: "npm run build",
        defaultPort: "3000"
    }
}
