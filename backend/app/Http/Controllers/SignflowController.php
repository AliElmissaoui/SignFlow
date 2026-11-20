<?php
namespace App\Http\Controllers;
use App\Models\{Company,User,SignDocument,SignStep};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB,Hash};
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
class SignflowController extends Controller {
 public function register(Request $r){$v=$r->validate(['name'=>'required|string|max:120','email'=>'required|email|unique:users,email','password'=>'required|string|min:10','company'=>'required|string|max:150']);return DB::transaction(function()use($v){$u=User::create(['name'=>$v['name'],'email'=>$v['email'],'password'=>Hash::make($v['password'])]);$c=Company::create(['name'=>$v['company'],'owner_id'=>$u->id]);$c->users()->attach($u->id,['role'=>'owner']);return response()->json(['token'=>$u->createToken('signflow')->plainTextToken,'user'=>$u,'company'=>$c],201);});}
 public function login(Request $r){$v=$r->validate(['email'=>'required|email','password'=>'required']);$u=User::where('email',$v['email'])->first();if(!$u||!Hash::check($v['password'],$u->password))throw ValidationException::withMessages(['email'=>['Identifiants incorrects']]);return ['token'=>$u->createToken('signflow')->plainTextToken,'user'=>$u];}
 public function logout(Request $r){$r->user()->currentAccessToken()->delete();return ['ok'=>true];}
 public function companies(Request $r){return $r->user()->companies()->get();}
 private function member(Request $r,int $company){$pivot=DB::table('company_user')->where('company_id',$company)->where('user_id',$r->user()->id)->first();abort_unless($pivot,403,'Entreprise non autorisée');return $pivot;}
 private function admin(Request $r,int $company){$p=$this->member($r,$company);abort_unless(in_array($p->role,['owner','admin']),403,'Administrateur requis');}
 public function team(Request $r,int $company){$this->member($r,$company);return Company::findOrFail($company)->users()->get(['users.id','users.name','users.email']);}
 public function addMember(Request $r,int $company){
  $this->admin($r,$company);
  Company::findOrFail($company);
  $v=$r->validate(['email'=>'required|email|max:255','role'=>'required|in:admin,manager,signer,viewer']);
  $email=Str::lower(trim($v['email']));
  $existing=User::whereRaw('LOWER(email) = ?',[$email])->first();
  if($existing && DB::table('company_user')->where('company_id',$company)->where('user_id',$existing->id)->exists()){
   return response()->json(['message'=>'Cet utilisateur est déjà membre de cette entreprise.'],422);
  }
  $token=Str::random(64);
  DB::table('company_invitations')->where('company_id',$company)->where('email',$email)->whereNull('accepted_at')->delete();
  DB::table('company_invitations')->insert([
   'company_id'=>$company,'invited_by'=>$r->user()->id,'email'=>$email,'role'=>$v['role'],
   'token_hash'=>hash('sha256',$token),'expires_at'=>now()->addDays(7),
   'created_at'=>now(),'updated_at'=>now()
  ]);
  // V0.3: lien à copier manuellement. Aucun email n'est envoyé automatiquement.
  return response()->json(['message'=>'Invitation créée. Partagez le lien avec le destinataire.',
   'invite_url'=>$r->getSchemeAndHttpHost().'/api/invitations/'.$token,
   'token'=>$token,'expires_in_days'=>7],201);
 }
 public function invitations(Request $r,int $company){
  $this->admin($r,$company);
  return DB::table('company_invitations')->where('company_id',$company)->whereNull('accepted_at')
   ->select('id','email','role','expires_at','created_at')->latest()->get();
 }
 public function registerInvited(Request $r,string $token){
  $v=$r->validate(['name'=>'required|string|max:120','email'=>'required|email|unique:users,email','password'=>'required|string|min:10']);
  return DB::transaction(function()use($v,$token){
   $invite=DB::table('company_invitations')->where('token_hash',hash('sha256',$token))->lockForUpdate()->first();
   abort_unless($invite && !$invite->accepted_at && $invite->expires_at>now(),404,'Invitation invalide ou expirée');
   abort_unless(Str::lower($v['email'])===Str::lower($invite->email),422,'Email différent de l’invitation');
   $u=User::create(['name'=>$v['name'],'email'=>$v['email'],'password'=>Hash::make($v['password'])]);
   DB::table('company_user')->insert(['company_id'=>$invite->company_id,'user_id'=>$u->id,'role'=>$invite->role,'created_at'=>now(),'updated_at'=>now()]);
   DB::table('company_invitations')->where('id',$invite->id)->update(['accepted_at'=>now(),'updated_at'=>now()]);
   return response()->json(['token'=>$u->createToken('signflow')->plainTextToken,'user'=>$u],201);
  });
 }
 public function invitationInfo(string $token){
  $invite=DB::table('company_invitations')->where('token_hash',hash('sha256',$token))
   ->whereNull('accepted_at')->where('expires_at','>',now())->first();
  abort_unless($invite,404,'Invitation invalide ou expirée');
  $company=Company::findOrFail($invite->company_id);
  return ['company'=>$company->name,'email'=>$invite->email,'role'=>$invite->role];
 }
 public function acceptInvitation(Request $r,string $token){
  return DB::transaction(function()use($r,$token){
   $invite=DB::table('company_invitations')->where('token_hash',hash('sha256',$token))->lockForUpdate()->first();
   abort_unless($invite && !$invite->accepted_at && $invite->expires_at>now(),404,'Invitation invalide ou expirée');
   $user=$r->user();
   abort_unless(Str::lower($user->email)===Str::lower($invite->email),403,'Connectez-vous avec l’adresse email invitée');
   DB::table('company_user')->updateOrInsert(['company_id'=>$invite->company_id,'user_id'=>$user->id],
    ['role'=>$invite->role,'updated_at'=>now(),'created_at'=>now()]);
   DB::table('company_invitations')->where('id',$invite->id)->update(['accepted_at'=>now(),'updated_at'=>now()]);
   return ['ok'=>true,'company_id'=>$invite->company_id];
  });
 }

 public function documents(Request $r,int $company){$this->member($r,$company);return SignDocument::where('company_id',$company)->where(function($q)use($r){$q->where('created_by',$r->user()->id)->orWhereHas('steps',fn($s)=>$s->where('user_id',$r->user()->id));})->with('steps')->latest()->get();}
 public function createDocument(Request $r,int $company){$p=$this->member($r,$company);abort_unless(in_array($p->role,['owner','admin','manager']),403);$v=$r->validate(['title'=>'required|string|max:200','signer_ids'=>'required|array|min:1|max:20','signer_ids.*'=>'required|integer|distinct|exists:users,id']);$allowed=DB::table('company_user')->where('company_id',$company)->whereIn('user_id',$v['signer_ids'])->count();abort_unless($allowed===count($v['signer_ids']),422,'Signataire hors entreprise');return DB::transaction(function()use($r,$company,$v){$d=SignDocument::create(['company_id'=>$company,'created_by'=>$r->user()->id,'title'=>$v['title']]);foreach($v['signer_ids'] as $i=>$id)$d->steps()->create(['user_id'=>$id,'position'=>$i+1]);DB::table('sign_events')->insert(['document_id'=>$d->id,'actor_id'=>$r->user()->id,'action'=>'created','created_at'=>now(),'updated_at'=>now()]);return response()->json($d->load('steps'),201);});}
 public function start(Request $r,int $company,int $document){$this->member($r,$company);return DB::transaction(function()use($r,$company,$document){$d=SignDocument::where('company_id',$company)->lockForUpdate()->findOrFail($document);abort_unless($d->created_by===$r->user()->id,403);abort_unless($d->status==='draft',409);$d->update(['status'=>'progress']);DB::table('sign_events')->insert(['document_id'=>$d->id,'actor_id'=>$r->user()->id,'action'=>'started','created_at'=>now(),'updated_at'=>now()]);return $d->load('steps');});}
 public function sign(Request $r,int $company,int $document){$this->member($r,$company);return DB::transaction(function()use($r,$company,$document){$d=SignDocument::where('company_id',$company)->lockForUpdate()->findOrFail($document);abort_unless($d->status==='progress',409,'Document non actif');$s=$d->steps()->where('status','pending')->orderBy('position')->first();abort_unless($s && $s->user_id===$r->user()->id,403,'Ce n’est pas votre tour');$s->update(['status'=>'signed','signed_at'=>now()]);if(!$d->steps()->where('status','pending')->exists())$d->update(['status'=>'signed']);DB::table('sign_events')->insert(['document_id'=>$d->id,'actor_id'=>$r->user()->id,'action'=>'step_approved','metadata'=>json_encode(['step_id'=>$s->id]),'created_at'=>now(),'updated_at'=>now()]);return $d->fresh()->load('steps');});}
}
