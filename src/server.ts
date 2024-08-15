import express, { Request, Response } from "express";
import cors from "cors";
import helmet from "helmet";

import keywords from "./keywords.json";

export const app: express.Application = express();

app.use(helmet());
if (process.env.CORS_HOST) {
  app.use(cors({ origin: process.env.CORS_HOST, credentials: true }));
}
app.use(express.json());

app.get("/", (req: Request, res: Response) => {
  res.json({
    keywords_url: "/keywords",
  });
});

app.get("/keywords", (req: Request, res: Response) => {
  res.json(keywords);
});

app.post("/keywords", (req: Request, res: Response) => {
  const keyword = req.body;
  if (!keyword.keyword) {
    res.status(400);
    res.json({ error: "invalid keyword" });
    return;
  }

  // Danger, Will Robinson!
  keywords.push(keyword);

  res.json(keyword);
});

app.get("/keywords/:keyword", (req: Request, res: Response) => {
  const keyword = req.params.keyword;

  if (!keyword) {
    notFound(res);
    return;
  }

  const matches = keywords.filter((obj) => {
    return obj.keyword === keyword;
  });

  if (matches.length === 0) {
    notFound(res);
    return;
  }

  return res.json(matches[0]);
});

const notFound = (res: Response) => {
  res.status(404);
  res.json({ error: "Not found" });
};
