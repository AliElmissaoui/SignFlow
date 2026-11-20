<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class SignDocument extends Model {protected $fillable=['company_id','created_by','title','status'];public function steps(){return $this->hasMany(SignStep::class,'document_id')->orderBy('position');}}
