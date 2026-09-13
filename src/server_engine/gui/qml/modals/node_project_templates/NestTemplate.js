function template() {
    return {
        id: "nest",
        title: "NestJS API",
        icon: "../icons/projects/nestjs.svg",
        description: "Structured backend with NestJS.",
        runtimeType: "api",
        minNodeVersion: "18.0.0",
        recommendedNodeVersion: "20.0.0",
        installCommand: "npm install",
        createCommand: "npx @nestjs/cli new",
        devCommand: "npm run dev",
        buildCommand: "npm run build",
        defaultPort: "3000"
    }
}
