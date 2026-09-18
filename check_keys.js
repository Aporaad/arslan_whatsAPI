const { Client } = require('pg');

const client = new Client({
  host: 'localhost',
  user: 'postgres',
  password: 'postgres',
  database: 'postgres',
  port: 5432,
});

async function run() {
  await client.connect();
  const tables = await client.query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'");
  console.log('Tables:', tables.rows.map(r => r.table_name));
  const apiKeyTable = tables.rows.find(r => r.table_name.includes('key'));
  if (apiKeyTable) {
    const keys = await client.query(`SELECT * FROM "${apiKeyTable.table_name}"`);
    console.log('Keys in', apiKeyTable.table_name, ':', keys.rows);
  }
  await client.end();
}

run().catch(console.error);
