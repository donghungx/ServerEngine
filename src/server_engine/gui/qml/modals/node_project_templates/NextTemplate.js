function template() {
    return {
        id: "next",
        title: "Next.js",
        icon: "../icons/projects/nextjs.svg",
        description: "Next.js app with routes and SSR.",
        runtimeType: "fullstack",
        minNodeVersion: "18.18.0",
        recommendedNodeVersion: "20.0.0",
        installCommand: "npm install",
        createCommand: "npx create-next-app@latest",
        devCommand: "npm run dev",
        buildCommand: "npm run build",
        defaultPort: "3000"
    }
}
