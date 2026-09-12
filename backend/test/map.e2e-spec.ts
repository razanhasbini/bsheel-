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
  it('creates audited places and shows a hidden one only as a locked pin, name and spot withheld',async()=>{
    const regular=await h.post('/map/admin/places',admin).send(input()).expect(201);
    // Off the regular place's exact coordinate so the blur is observable.
    const hidden=await h.post('/map/admin/places',admin).send({...input('hidden'),latitude:33.91234,longitude:35.51234}).expect(201);
    placeId=regular.body.data.id;hiddenId=hidden.body.data.id;places.push(placeId,hiddenId);h.track(...places);
    const result=await h.get('/map/places?country=LB',user).expect(200);
    expect(result.body.data.some((p:{id:string})=>p.id===placeId)).toBe(true);
    // The pin is there — that is the invitation — but nothing that identifies it.
    const pin=result.body.data.find((p:{id:string})=>p.id===hiddenId);
    expect(pin).toMatchObject({locked:true,name:'Locked location',description:'',city:'',quest_count:0});
    expect(pin.latitude).not.toBe(33.91234);expect(pin.longitude).not.toBe(35.51234);
    expect(Math.abs(pin.latitude-33.91234)).toBeLessThan(0.01);
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
  // The game's progression (migration 0035 model): a hidden place and its
  // quests stay out of reach until the player has an APPROVED quest at any
  // place within 10 km; a takedown closes the fog again. Presence itself is
  // no longer checked before assignment — the geofence opens afterwards and
  // the network's answer is weighed when the proof comes in.
  it('reveals a hidden place through an approved quest nearby, and re-hides it on takedown',async()=>{
    const secret=await h.createQuest();
    await h.post(`/map/admin/places/${hiddenId}/quests`,admin).send({questId:secret.id,requiresVerification:true}).expect(201);
    // Nothing confirmed nearby yet (the earlier discovery was taken down).
    await h.get(`/quests/${secret.id}`,user).expect(404);
    await h.post('/quests/assign',user).send({questId:secret.id}).expect(404);
    await h.get(`/map/places/${hiddenId}`,user).expect(404);

    // Earn it: an approved quest at the regular place ~1.7 km away.
    const nearby=await h.createQuest();
    await h.post(`/map/admin/places/${placeId}/quests`,admin).send({questId:nearby.id,requiresVerification:false}).expect(201);
    const proof=await h.createSubmission(user,{questId:nearby.id});
    await h.get(`/map/places/${hiddenId}`,user).expect(404); // pending is not enough
    await h.post(`/submissions/${proof.id}/approve`,admin).send({}).expect(204);

    const revealed=await h.get(`/map/places/${hiddenId}`,user).expect(200);
    expect(revealed.body.data.quests[0]).toMatchObject({id:secret.id,unlocked:true,requires_verification:true});
    const pins=await h.get('/map/places?country=LB',user).expect(200);
    expect(pins.body.data.find((p:{id:string})=>p.id===hiddenId)).toMatchObject({locked:false,latitude:33.91234,longitude:35.51234});
    await h.get(`/quests/${secret.id}`,user).expect(200);
    // Other players see nothing: discovery is per account.
    await h.get(`/map/places/${hiddenId}`,other).expect(404);
    await h.get(`/quests/${secret.id}`,other).expect(404);

    // A published destination can be started without any pre-verification;
    // an unpublished one still cannot, even by raw insert.
    await h.database.query('UPDATE map_places SET is_published=false WHERE id=$1',[hiddenId]);
    await expect(h.database.query("INSERT INTO user_quests(user_id,quest_id,expires_at) VALUES($1,$2,now()+interval '1 hour')",[user.id,secret.id])).rejects.toMatchObject({code:'23514'});
    await h.database.query('UPDATE map_places SET is_published=true WHERE id=$1',[hiddenId]);

    // Takedown withdraws the discovery and the fog closes.
    await h.database.query('UPDATE submissions SET moderation_removed_at=now() WHERE id=$1',[proof.id]);
    await h.get(`/map/places/${hiddenId}`,user).expect(404);
    await h.get(`/quests/${secret.id}`,user).expect(404);
  });

  // Exploration progress (#66): one authoritative model, approved-only,
  // unique places. Pending, rejected, repeated and non-location completions
  // move nothing.
  it('counts exploration from approved destination quests only, once per place',async()=>{
    const pct=async()=>{
      const r=await h.get('/map/progress/me',user).expect(200);
      return {world:r.body.data.world,lb:r.body.data.countries.find((c:{countryCode:string})=>c.countryCode==='LB')};
    };
    const before=await pct();
    const baseExplored=before.lb.exploredPlaces as number;

    // Pending proof at a fresh place: nothing moves.
    const spot=await h.post('/map/admin/places',admin).send(input()).expect(201);
    places.push(spot.body.data.id);
    const q1=await h.createQuest();
    await h.post(`/map/admin/places/${spot.body.data.id}/quests`,admin).send({questId:q1.id,requiresVerification:false}).expect(201);
    const pending=await h.createSubmission(user,{questId:q1.id});
    expect((await pct()).lb.exploredPlaces).toBe(baseExplored);
    expect((await pct()).lb.pendingPlaces).toBeGreaterThanOrEqual(1);

    // Approved: the place counts, once, and the world moves with it.
    await h.post(`/submissions/${pending.id}/approve`,admin).send({}).expect(204);
    const after=await pct();
    expect(after.lb.exploredPlaces).toBe(baseExplored+1);
    expect(after.lb.percentage).toBeGreaterThan(before.lb.percentage);
    expect(after.world.exploredPlaces).toBe((before.world.exploredPlaces as number)+1);

    // A second approved quest at the SAME place is not a second discovery.
    const q2=await h.createQuest();
    await h.post(`/map/admin/places/${spot.body.data.id}/quests`,admin).send({questId:q2.id,requiresVerification:false}).expect(201);
    const again=await h.createSubmission(user,{questId:q2.id});
    await h.post(`/submissions/${again.id}/approve`,admin).send({}).expect(204);
    expect((await pct()).lb.exploredPlaces).toBe(baseExplored+1);

    // A quest with no destination — a home/learning quest — never counts.
    const home=await h.createQuest();
    const homeProof=await h.createSubmission(user,{questId:home.id});
    await h.post(`/submissions/${homeProof.id}/approve`,admin).send({}).expect(204);
    expect((await pct()).lb.exploredPlaces).toBe(baseExplored+1);

    // Other players' progress is their own.
    const others=await h.get('/map/progress/me',other).expect(200);
    expect(others.body.data.countries.find((c:{countryCode:string})=>c.countryCode==='LB').exploredPlaces).toBe(0);
  });

  it('describes a country from anywhere: trending, discovery, and how much is hidden',async()=>{
    await h.get('/map/countries/XX/discover',user).expect(404);
    await h.get('/map/countries/lb/discover',user).expect(400);
    const r=await h.get('/map/countries/LB/discover',user).expect(200);
    const d=r.body.data;
    expect(d.country).toMatchObject({code:'LB',name:'Lebanon'});
    expect(d.country.percentage).toBeGreaterThan(0);
    // The quest the user completed above has engagement, so it trends; a
    // trending quest is never also a discovery pick.
    const trendingIds=d.trending.map((q:{id:string})=>q.id);
    expect(trendingIds.length).toBeGreaterThan(0);
    for(const q of d.discovery)expect(trendingIds).not.toContain(q.id);
    for(const q of [...d.trending,...d.discovery]){
      expect(q).toHaveProperty('place_id');expect(q).toHaveProperty('latitude');expect(q).toHaveProperty('completed');
      expect(q).not.toHaveProperty('engagement');
    }
    // A genuinely hidden quest is counted, never listed.
    const secret=await h.createQuest();
    await h.database.query('UPDATE quests SET is_hidden=true WHERE id=$1',[secret.id]);
    await h.post(`/map/admin/places/${placeId}/quests`,admin).send({questId:secret.id,requiresVerification:false}).expect(201);
    const r2=await h.get('/map/countries/LB/discover',user).expect(200);
    const all=[...r2.body.data.trending,...r2.body.data.discovery].map((q:{id:string})=>q.id);
    expect(all).not.toContain(secret.id);
    expect(r2.body.data.hiddenCount).toBeGreaterThanOrEqual(1);
    expect(Array.isArray(r2.body.data.collections)).toBe(true);
  });

  // Admin manageability (#48). The console could create a place and link a
  // quest, then nothing: no way to see existing links, undo a mis-link, or
  // publish a draft. Because destination assignment is blocked while a place
  // is unpublished, a bad link could leave a quest quietly unassignable with
  // no route back.
  // The moments layer (Snap/Instagram-map shaped). Everything it shows is
  // already on the feed; what this pins is that it shows nothing more, and
  // that the coordinate it hands the client is the PLACE's.
  describe('moments', () => {
    let momentPlace:string,momentQuest:string,momentProof:string;
    beforeAll(async()=>{
      const created=await h.post('/map/admin/places',admin).send(input()).expect(201);
      momentPlace=created.body.data.id;places.push(momentPlace);h.track(momentPlace);
      const quest=await h.createQuest();momentQuest=quest.id;
      await h.post(`/map/admin/places/${momentPlace}/quests`,admin).send({questId:momentQuest,requiresVerification:false}).expect(201);
      const proof=await h.createSubmission(user,{questId:momentQuest});momentProof=proof.id;
    });
    const moments=async(as:TestUser)=>(await h.get('/map/moments?country=LB',as).expect(200)).body.data as Record<string,unknown>[];
    const mine=async(as:TestUser)=>(await moments(as)).filter(m=>m.id===momentProof);

    it('shows nothing until the proof is approved and public', async()=>{
      // Pending proof is not a moment: the feed does not show it either.
      expect(await mine(user)).toEqual([]);
      await h.post(`/submissions/${momentProof}/approve`,admin).send({}).expect(204);
      const [moment]=await mine(user);
      expect(moment).toMatchObject({place_id:momentPlace,quest_id:momentQuest,media_type:'image',username:user.username});
      // The PLACE's coordinate and radius — not a location for the person.
      // The client scatters the tiles inside the radius; the API never
      // pretends to know where somebody stood.
      expect(moment).toMatchObject({latitude:33.9,longitude:35.5,radius_m:250});
    });

    it('is visible to everyone the feed is visible to', async()=>{
      expect((await mine(other))).toHaveLength(1);
    });

    it('drops proof its author kept off the feed', async()=>{
      await h.database.query('UPDATE submissions SET show_in_feed=false WHERE id=$1',[momentProof]);
      expect(await mine(user)).toEqual([]);
      await h.database.query('UPDATE submissions SET show_in_feed=true WHERE id=$1',[momentProof]);
      expect(await mine(user)).toHaveLength(1);
    });

    it('drops proof a moderator took down', async()=>{
      await h.database.query('UPDATE submissions SET moderation_removed_at=now() WHERE id=$1',[momentProof]);
      expect(await mine(user)).toEqual([]);
      await h.database.query('UPDATE submissions SET moderation_removed_at=NULL WHERE id=$1',[momentProof]);
    });

    it('hides a blocked account\'s proof in both directions', async()=>{
      await h.database.query('INSERT INTO blocked_users(blocker_id,blocked_id) VALUES($1,$2)',[other.id,user.id]);
      expect(await mine(other)).toEqual([]);
      await h.database.query('DELETE FROM blocked_users WHERE blocker_id=$1 AND blocked_id=$2',[other.id,user.id]);
      await h.database.query('INSERT INTO blocked_users(blocker_id,blocked_id) VALUES($1,$2)',[user.id,other.id]);
      expect(await mine(other)).toEqual([]);
      await h.database.query('DELETE FROM blocked_users WHERE blocker_id=$1 AND blocked_id=$2',[user.id,other.id]);
    });

    it('never shows a hidden quest, even at a place everyone can see', async()=>{
      // The one most worth getting right. A later stage of a journey, or a
      // quest that unlocks by reaching somewhere, is content the player is
      // meant to discover. A tile of somebody else finishing it gives away
      // that it exists and roughly where — the game's surprise, spent by a
      // photograph. The place here is deliberately an ordinary visible one,
      // so nothing but `is_hidden` is doing the work.
      // Completed while the quest was ordinary — a hidden quest cannot be
      // assigned through the normal endpoint, which is the unlock gate doing
      // its job. Hiding it afterwards is also the real case: a quest becomes
      // a journey's later stage after people have already played it.
      const hiddenQuest=await h.createQuest();
      await h.post(`/map/admin/places/${momentPlace}/quests`,admin).send({questId:hiddenQuest.id,requiresVerification:false}).expect(201);
      const proof=await h.createSubmission(other,{questId:hiddenQuest.id});
      await h.post(`/submissions/${proof.id}/approve`,admin).send({}).expect(204);
      expect((await moments(user)).some(m=>m.id===proof.id)).toBe(true);

      await h.database.query('UPDATE quests SET is_hidden=true WHERE id=$1',[hiddenQuest.id]);
      // Gone for a stranger, and gone for the person who completed it too:
      // a per-viewer rule here leaks the moment it is slightly wrong.
      expect((await moments(user)).some(m=>m.id===proof.id)).toBe(false);
      expect((await moments(other)).some(m=>m.id===proof.id)).toBe(false);
    });

    it('never leaks a locked place', async()=>{
      // A hidden place withholds its name and blurs its position; a moment
      // at one would hand back both, plus somebody's photograph. `user`
      // earned the reveal here (an approved quest within 10 km), a third
      // account never did — which is the asymmetry to check.
      await h.database.query('UPDATE map_places SET is_published=true WHERE id=$1',[hiddenId]);
      const nearby=await h.createQuest();
      await h.post(`/map/admin/places/${placeId}/quests`,admin).send({questId:nearby.id,requiresVerification:false}).expect(201);
      const reveal=await h.createSubmission(user,{questId:nearby.id});
      await h.post(`/submissions/${reveal.id}/approve`,admin).send({}).expect(204);

      const secret=await h.createQuest();
      await h.post(`/map/admin/places/${hiddenId}/quests`,admin).send({questId:secret.id,requiresVerification:false}).expect(201);
      const proof=await h.createSubmission(user,{questId:secret.id});
      await h.post(`/submissions/${proof.id}/approve`,admin).send({}).expect(204);

      const third=await h.createUser({prefix:'mapthird'});
      expect((await moments(third)).some(m=>m.place_id===hiddenId)).toBe(false);
      expect((await moments(user)).some(m=>m.place_id===hiddenId)).toBe(true);
    });

    it('draws one tile per place and counts the rest as "+N more"', async()=>{
      // The Snap/Instagram-map shape. Without it a landmark with two hundred
      // completions buries every other place on the board and the map stops
      // being a map. The count is what keeps the summary honest: the tile
      // says how much it is standing in front of.
      const before=(await moments(user)).filter(m=>m.place_id===momentPlace);
      expect(before).toHaveLength(1);
      const countedBefore=Number(before[0].more_count);

      const busy=await h.createQuest();
      await h.post(`/map/admin/places/${momentPlace}/quests`,admin).send({questId:busy.id,requiresVerification:false}).expect(201);
      for (const who of [await h.createUser({prefix:'mapbusy1'}),await h.createUser({prefix:'mapbusy2'}),await h.createUser({prefix:'mapbusy3'})]) {
        const proof=await h.createSubmission(who,{questId:busy.id});
        await h.post(`/submissions/${proof.id}/approve`,admin).send({}).expect(204);
      }

      const here=(await moments(user)).filter(m=>m.place_id===momentPlace);
      expect(here).toHaveLength(1);
      // Three more standing here than before, and the tile says so rather
      // than three more tiles appearing.
      expect(Number(here[0].more_count)).toBe(countedBefore+3);
      // And it carries what there is to DO here — the reason a photograph is
      // on a map at all.
      expect(Number(here[0].quest_count)).toBeGreaterThan(0);
    });

    it('requires authentication and bounds the list', async()=>{
      await h.get('/map/moments').expect(401);
      await h.get('/map/moments?limit=500',user).expect(400);
      expect((await h.get('/map/moments?limit=1',user).expect(200)).body.data).toHaveLength(1);
    });
  });

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