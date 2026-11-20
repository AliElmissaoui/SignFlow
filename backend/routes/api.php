<?php
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\SignflowController as S;
Route::post('/register',[S::class,'register']);
Route::post('/login',[S::class,'login']);
Route::post('/invitations/{token}/register',[S::class,'registerInvited']);
Route::get('/invitations/{token}',[S::class,'invitationInfo']);
Route::middleware('auth:sanctum')->group(function(){
 Route::post('/invitations/{token}/accept',[S::class,'acceptInvitation']);
 Route::get('/companies/{company}/invitations',[S::class,'invitations']);
 Route::post('/logout',[S::class,'logout']);
 Route::get('/companies',[S::class,'companies']);
 Route::get('/companies/{company}/team',[S::class,'team']);
 Route::post('/companies/{company}/team',[S::class,'addMember']);
 Route::get('/companies/{company}/documents',[S::class,'documents']);
 Route::post('/companies/{company}/documents',[S::class,'createDocument']);
 Route::post('/companies/{company}/documents/{document}/start',[S::class,'start']);
 Route::post('/companies/{company}/documents/{document}/sign',[S::class,'sign']);
});
