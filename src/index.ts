import { app } from './server';

const port = process.env.PORT || '3000';

const server = app.listen(parseInt(port), function () {
  console.info(`Server is listening on http://localhost:${port}`);
})

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

function shutdown() {
  console.info(`Shutting down server...`);
  server.close();
}
