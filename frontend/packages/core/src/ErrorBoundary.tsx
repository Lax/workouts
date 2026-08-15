import type { ErrorInfo, ReactNode } from 'react'
import { Component } from 'react'

interface Props {
  children: ReactNode
}

interface State {
  hasError: boolean
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false }

  static getDerivedStateFromError(): State {
    return { hasError: true }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[@git-fit/core] Layout render crashed:', error, info.componentStack)
  }

  render() {
    return this.state.hasError ? null : this.props.children
  }
}
