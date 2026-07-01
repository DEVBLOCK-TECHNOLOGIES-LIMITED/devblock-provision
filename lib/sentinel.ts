// DevBlock Sentinel SDK — auto-injected by DevBlock Console
import { DSentinel } from '@devblock/sentinel';

const sentinel = new DSentinel({
  apiKey: 'dk_08c8b096ae404ab790faeb36',
  serverUrl: 'https://devblock-console-server.devblocktechnologies.workers.dev',
  debug: process.env.NODE_ENV !== 'production',
});

// Auto-start — logs begin streaming immediately
sentinel.start();

// Track app lifecycle
sentinel.info('Application started', {
  project: 'Devblock Provision',
  environment: 'DEVELOPMENT'
});

// Export for manual use throughout your app
export { sentinel };
export default sentinel;
