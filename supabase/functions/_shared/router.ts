export type Handler = (
  req: Request,
  params: Record<string, string>,
  supa: ReturnType<typeof import('./auth.ts').createServiceClient>,
  userId: string,
  userRow: Record<string, unknown>,
) => Promise<Response>

interface Route {
  method: string
  pattern: URLPattern
  handler: Handler
}

export class Router {
  private routes: Route[] = []

  add(method: string, path: string, handler: Handler) {
    this.routes.push({
      method: method.toUpperCase(),
      pattern: new URLPattern({ pathname: path }),
      handler,
    })
  }

  get(path: string, handler: Handler) { this.add('GET', path, handler) }
  post(path: string, handler: Handler) { this.add('POST', path, handler) }
  put(path: string, handler: Handler) { this.add('PUT', path, handler) }
  delete(path: string, handler: Handler) { this.add('DELETE', path, handler) }

  match(method: string, url: string): { handler: Handler; params: Record<string, string> } | null {
    for (const route of this.routes) {
      if (route.method !== method.toUpperCase()) continue
      const result = route.pattern.exec(url)
      if (result) {
        const params = Object.fromEntries(
          Object.entries(result.pathname.groups).map(([k, v]) => [k, v ?? '']),
        )
        return { handler: route.handler, params }
      }
    }
    return null
  }
}
