// Bun imports a stylesheet as its text (`with { type: "text" }`), for the overlay's shadow root.
declare module "*.css" {
  const text: string
  export default text
}
