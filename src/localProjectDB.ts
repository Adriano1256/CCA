export type StoredMediaRecord = {
  id: string;
  name: string;
  size: number;
  type: string;
  lastModified: number;
  kind: 'Vídeo' | 'Imagem' | 'Áudio';
  order: number;
  duration?: number;
  blob: Blob;
};

export type ProjectSnapshot = {
  schemaVersion: number;
  projectName: string;
  profile: string;
  media: Array<Pick<StoredMediaRecord, 'id' | 'name' | 'size' | 'kind' | 'order' | 'duration'>>;
  clips: Array<{ id: string; mediaId: string; track: string; start: number; duration: number; sourceIn?: number; label: string }>;
  updatedAt: string;
};

const DB_NAME = 'editor-ia-local';
const DB_VERSION = 1;
const PROJECT_STORE = 'projects';
const MEDIA_STORE = 'media';

function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    if (!('indexedDB' in window)) return reject(new Error('Este navegador não oferece armazenamento local compatível.'));
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(PROJECT_STORE)) db.createObjectStore(PROJECT_STORE, { keyPath: 'id' });
      if (!db.objectStoreNames.contains(MEDIA_STORE)) db.createObjectStore(MEDIA_STORE, { keyPath: 'id' });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('Falha ao abrir o banco local.'));
  });
}

function requestResult<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('Falha no armazenamento local.'));
  });
}

export async function saveMediaRecord(record: StoredMediaRecord): Promise<void> {
  const db = await openDatabase();
  try {
    const tx = db.transaction(MEDIA_STORE, 'readwrite');
    tx.objectStore(MEDIA_STORE).put(record);
    await new Promise<void>((resolve, reject) => {
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error ?? new Error('Não foi possível salvar a mídia.'));
      tx.onabort = () => reject(tx.error ?? new Error('Salvamento da mídia cancelado.'));
    });
  } finally { db.close(); }
}

export async function loadMediaRecords(): Promise<StoredMediaRecord[]> {
  const db = await openDatabase();
  try {
    const tx = db.transaction(MEDIA_STORE, 'readonly');
    return await requestResult(tx.objectStore(MEDIA_STORE).getAll()) as StoredMediaRecord[];
  } finally { db.close(); }
}

export async function saveProjectSnapshot(snapshot: ProjectSnapshot): Promise<void> {
  const db = await openDatabase();
  try {
    const tx = db.transaction(PROJECT_STORE, 'readwrite');
    tx.objectStore(PROJECT_STORE).put({ id: 'active-project', ...snapshot });
    await new Promise<void>((resolve, reject) => {
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error ?? new Error('Não foi possível salvar o projeto.'));
      tx.onabort = () => reject(tx.error ?? new Error('Salvamento do projeto cancelado.'));
    });
  } finally { db.close(); }
}

export async function loadProjectSnapshot(): Promise<ProjectSnapshot | null> {
  const db = await openDatabase();
  try {
    const tx = db.transaction(PROJECT_STORE, 'readonly');
    const value = await requestResult(tx.objectStore(PROJECT_STORE).get('active-project')) as (ProjectSnapshot & { id: string }) | undefined;
    if (!value) return null;
    const { id: _id, ...snapshot } = value;
    return snapshot;
  } finally { db.close(); }
}
