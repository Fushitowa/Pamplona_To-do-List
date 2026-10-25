# Supabase setup

1. In the Supabase dashboard, create or open a project.
2. In **SQL Editor**, run the current contents of `migrations/20261025000000_create_tasks.sql`. It creates the app-specific `public.lexterbeat_tasks` table and leaves any existing `public.tasks` table untouched.
3. In **Authentication → Sign In / Providers**, enable **Anonymous Sign-Ins**. The app creates a separate anonymous account in each browser and uses row-level security to keep task rows private to that account.
4. Copy the project URL and the **publishable** API key from **Project Settings → API Keys** into a local `.env` file, using `.env.example` as the template. Do not put a `service_role` or secret key in a browser app.
5. Restart the Vite dev server after adding `.env`. The app imports existing local tasks once for the browser's anonymous account, then syncs task changes to Supabase.

Anonymous accounts cannot be recovered after browser data is cleared and do not follow the user to another browser or device. Add a permanent sign-in method before relying on this database for cross-device access.
