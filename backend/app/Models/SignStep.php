<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class SignStep extends Model {protected $fillable=['document_id','user_id','position','status','signed_at'];protected function casts():array{return ['signed_at'=>'datetime'];}}
