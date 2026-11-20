<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Company extends Model {protected $fillable=['name','owner_id'];public function users(){return $this->belongsToMany(User::class)->withPivot('role')->withTimestamps();}}
