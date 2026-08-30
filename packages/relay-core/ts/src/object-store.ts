export interface ListPrefixItem {
  Key?: string;
  LastModified?: Date | null;
}

export interface ListPrefixPageResult {
  contents: ListPrefixItem[];
  nextContinuationToken: string | null;
  isTruncated: boolean;
}

export interface ObjectStore {
  putObject(
    key: string,
    body: Buffer | string,
    contentType?: string,
    tagging?: string,
    ifMatch?: string,
    ifNoneMatch?: string,
  ): Promise<unknown>;

  getObject(key: string): Promise<unknown | null>;

  getJsonWithEtag(key: string): Promise<{ body: unknown; etag: string | null } | null>;

  deleteObject(key: string): Promise<unknown>;

  deleteObjects(keys: string[]): Promise<unknown>;

  listPrefixPage(prefix: string, continuationToken?: string, maxKeys?: number): Promise<ListPrefixPageResult>;
}
