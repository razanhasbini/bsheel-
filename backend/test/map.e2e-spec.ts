import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

describe('map destinations and discovery', {timeout:120000}, () => {
  let h:E2eHarness,admin:TestUser,user:TestUser,other:TestUser;
  let placeId:string,hiddenId:string,questId:string,submissionId:string;
  const places:string[]=[];
  beforeAll(async()=>{
    h=await E2eHarness.boot();
    admin=await h.createUser({role:'super_admin',prefix:'mapadmin'});
    user=await h.createUser({prefix:'mapviewer'});
    other=await h.createUser({prefix:'mapother'});
  },300000);
  afterAll(async()=>{
    if(!h)return;
    await h.database.query('DELETE FROM quest_destinations WHERE place_id=ANY($1::uuid[])',[places]);
    await h.database.query('DELETE FROM map_places WHERE id=ANY($1::uuid[])',[places]);
    await h.close();
  });
  const input=(category='landmark')=>({countryCode:'LB',countryName:'Lebanon',geometryId:'422',name:`Map test ${randomUUID()}`,description:'Test fixture, not a published travel recommendation',city:'Test',category,latitude:33.9,longitude:35.5,radiusM:250,isPublished:true});

  it('requires authentication and staff authorization',async()=>{
    await h.get('/map/places').expect(401);
    await h.post('/map/admin/places',user).send(input()).expect(403);
    await h.post('/map/admin/places',admin).send({...input(),latitude:100}).expect(400);
  });
  it('creates audited places but withholds hidden names and coordinates',async()=>{
    const regular=await h.post('/map/admin/places',admin).send(input()).expect(201);
    const hidden=await h.post('/map/admin/places',admin).send(input('hidden')).expect(201);
    placeId=regular.body.data.id;hiddenId=hidden.body.data.id;places.push(placeId,hiddenId);h.track(...places);
    const result=await h.get('/map/places?country=LB',user).expect(200);
    expect(result.body.data.some((p:{id:string})=>p.id===placeId)).toBe(true);
    expect(result.body.data.some((p:{id:string})=>p.id===hiddenId)).toBe(false);
    await h.get(`/map/places/${hiddenId}`,user).expect(404);
    const hiddenSearch=await h.get(`/map/places?search=${encodeURIComponent(hidden.body.data.name)}`,user).expect(200);
    expect(hiddenSearch.body.data).toEqual([]);
    expect(await h.countRows("SELECT count(*) FROM admin_audit_log WHERE action='map.place.create' AND target_id=$1",[placeId])).toBe(1);
  });
  it('saves idempotently without granting discovery and isolates accounts',async()=>{
    await h.post(`/map/places/${placeId}/save`,user).expect(201);
    await h.post(`/map/places/${placeId}/save`,user).expect(201);
    expect(await h.countRows('SELECT count(*) FROM saved_map_places WHERE user_id=$1 AND place_id=$2',[user.id,placeId])).toBe(1);
    const countries=await h.get('/map/countries',user).expect(200);
    expect(countries.body.data.find((c:{code:string})=>c.code==='LB').discovered).toBe(0);
    const others=await h.get('/map/places',other).expect(200);
    expect(others.body.data.find((p:{id:string})=>p.id===placeId).saved).toBe(false);
  });
  it('keeps location-independent destination quests working and provisional until approval',async()=>{
    const quest=await h.createQuest();questId=quest.id;
    await h.post(`/map/admin/places/${placeId}/quests`,admin).send({questId,requiresVerification:false}).expect(201);
    const detail=await h.get(`/map/places/${placeId}`,user).expect(200);
    expect(detail.body.data.quests[0].unlocked).toBe(true);
    const submission=await h.createSubmission(user,{questId});submissionId=submission.id;
    let country=(await h.get('/map/countries',user).expect(200)).body.data.find((c:{code:string})=>c.code==='LB');
    expect(country.discovered).toBe(1);expect(country.confirmed).toBe(0);
    await h.post(`/submissions/${submissionId}/approve`,admin).send({}).expect(204);
    country=(await h.get('/map/countries',user).expect(200)).body.data.find((c:{code:string})=>c.code==='LB');
    expect(country.discovered).toBe(1);expect(country.confirmed).toBe(1);
    await h.post(`/map/admin/places/${placeId}/quests`,admin).send({questId,requiresVerification:false}).expect(409);
  });
  it('revokes discovery for moderator takedowns and never counts bookmarks',async()=>{
    await h.database.query('UPDATE submissions SET moderation_removed_at=now() WHERE id=$1',[submissionId]);
    const country=(await h.get('/map/countries',user).expect(200)).body.data.find((c:{code:string})=>c.code==='LB');
    expect(country.discovered).toBe(0);expect(country.confirmed).toBe(0);expect(country.saved).toBe(1);
  });
  // Migration 0035 deliberately narrowed the database guard. The original
  // version required all three location signals BEFORE an assignment could
  // exist, which the real lifecycle cannot satisfy: the geofence
  // subscription is created *by* the assignment, so the evidence it produces
  // cannot predate it. Verification moved to submission time, in the agent
  // pipeline. What the trigger still guarantees is the part that has no such
  // ordering problem — an unpublished destination is never assignable.
  //
  // So this asserts the guard that exists rather than the one that was
  // removed. Hidden-place *visibility* is still gated on all three signals,
  // which is what the rest of this case covers.
  it('blocks assignment of an unpublished destination, and gates hidden place detail on all three signals',async()=>{
    const quest=await h.createQuest();
    await h.post(`/map/admin/places/${hiddenId}/quests`,admin).send({questId:quest.id,requiresVerification:true}).expect(201);
    await h.get(`/quests/${quest.id}`,user).expect(404);
    await h.post('/quests/assign',user).send({questId:quest.id}).expect(404);

    // Unpublished is still refused at the database, on every path.
    const draft=await h.post('/map/admin/places',admin).send({...input(),isPublished:false}).expect(201);
    places.push(draft.body.data.id);
    const draftQuest=await h.createQuest();
    await h.post(`/map/admin/places/${draft.body.data.id}/quests`,admin).send({questId:draftQuest.id,requiresVerification:false}).expect(201);
    await expect(h.database.query("INSERT INTO user_quests(user_id,quest_id,expires_at) VALUES($1,$2,now()+interval '1 hour')",[user.id,draftQuest.id])).rejects.toMatchObject({code:'23514'});

    const reference=randomUUID();
    await h.database.query(`INSERT INTO map_location_evidence(user_id,place_id,provider_reference,location_verified,location_retrieved,geofence_verified,verified_at,expires_at)
      VALUES($1,$2,$3,true,true,false,now(),now()+interval '5 minutes')`,[user.id,hiddenId,reference]);
    await h.get(`/map/places/${hiddenId}`,user).expect(404);
    await h.database.query('UPDATE map_location_evidence SET geofence_verified=true WHERE provider_reference=$1',[reference]);
    await h.get(`/map/places/${hiddenId}`,user).expect(200);
    await h.get(`/map/places/${hiddenId}`,other).expect(404);
    await h.get(`/quests/${quest.id}`,user).expect(200);
    await h.database.query("UPDATE map_location_evidence SET verified_at=now()-interval '10 minutes',expires_at=now()-interval '1 minute' WHERE provider_reference=$1",[reference]);
    await h.get(`/map/places/${hiddenId}`,user).expect(404);
  });

  // Admin manageability (#48). The console could create a place and link a
  // quest, then nothing: no way to see existing links, undo a mis-link, or
  // publish a draft. Because destination assignment is blocked while a place
  // is unpublished, a bad link could leave a quest quietly unassignable with
  // no route back.
  describe('admin place management', () => {
    /// Creates a place and registers it for afterAll cleanup.
    const makePlace = async (overrides: Record<string, unknown> = {}) => {
      const created = await h.post('/map/admin/places', admin)
        .send({ ...input(), ...overrides }).expect(201);
      places.push(created.body.data.id);
      return created.body.data.id as string;
    };

    it('reports a quest count on the admin list', async () => {
      const placeId = await makePlace();
      const list = await h.get('/map/admin/places', admin).expect(200);
      const row = (list.body.data as Record<string, unknown>[]).find((p) => p.id === placeId);
      // Zero, not absent: the console has to tell "no quests" apart from
      // "the endpoint does not say", which is what it showed before.
      expect(row?.quest_count).toBe(0);
    });

    it('shows a draft place and its links to staff, which public detail hides', async () => {
      const quest = await h.createQuest({ title: 'linked to a draft' });
      const placeId = await makePlace({ isPublished: false });
      await h.post(`/map/admin/places/${placeId}/quests`, admin)
        .send({ questId: quest.id, requiresVerification: false }).expect(201);

      const detail = await h.get(`/map/admin/places/${placeId}`, admin).expect(200);
      expect(detail.body.data.is_published).toBe(false);
      expect((detail.body.data.quests as { id: string }[]).map((q) => q.id)).toContain(quest.id);
    });

    it('unlinks a mis-linked quest, and refuses once it has attempts', async () => {
      const quest = await h.createQuest({ title: 'mis-linked' });
      const placeId = await makePlace();
      await h.post(`/map/admin/places/${placeId}/quests`, admin)
        .send({ questId: quest.id, requiresVerification: false }).expect(201);

      await h.delete(`/map/admin/places/${placeId}/quests/${quest.id}`, admin).expect(200);
      const after = await h.get(`/map/admin/places/${placeId}`, admin).expect(200);
      expect(after.body.data.quests).toHaveLength(0);

      // Unlinking a quest people already attempted would retroactively move
      // their discovery, so it is refused for the same reason linking is.
      const started = await h.createQuest({ title: 'already attempted' });
      await h.post(`/map/admin/places/${placeId}/quests`, admin)
        .send({ questId: started.id, requiresVerification: false }).expect(201);
      const player = await h.createUser({ prefix: 'mapplay' });
      await h.assignQuest(player, started.id);
      const refused = await h
        .delete(`/map/admin/places/${placeId}/quests/${started.id}`, admin).expect(409);
      expect(refused.body.error.code).toBe('QUEST_ALREADY_STARTED');
    });

    it('publishes a draft place, which was fixed at creation before', async () => {
      const placeId = await makePlace({ isPublished: false, category: 'culture' });
      const updated = await h.patch(`/map/admin/places/${placeId}`, admin)
        .send({ isPublished: true, radiusM: 500 }).expect(200);
      expect(updated.body.data.is_published).toBe(true);
      expect(updated.body.data.radius_m).toBe(500);
    });

    it('refuses management to a non-super-admin', async () => {
      await h.get('/map/admin/places', user).expect(403);
      await h.patch(`/map/admin/places/${placeId}`, user).send({ isPublished: false }).expect(403);
    });
  });
});