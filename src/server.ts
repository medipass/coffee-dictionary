import express, { Request, Response } from 'express';
import cors from 'cors';
import helmet from 'helmet';

import keywords from './keywords.json';

export const app: express.Application = express();

app.use(helmet());
if (process.env.CORS_HOST) {
  app.use(cors({ origin: process.env.CORS_HOST, credentials: true }));
}
app.use(express.json());

app.get('/', (req: Request, res: Response) => {
  res.json({
    "keywords_url": "/keywords"
  });
});
app.get('/keywords', (req: Request, res: Response) => {
  res.json(keywords);
});
